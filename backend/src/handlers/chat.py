"""
POST /chat: text-based conversation via Claude with SSE streaming.

SSE event format (each line: "data: <json>\n\n"):
  {"type": "text_delta",      "delta": str}
  {"type": "tool_thinking",   "message": str}
  {"type": "clarification_ui","clarification_id": str, "question": str,
                               "options": list[str], "multi_select": bool}
  {"type": "done",            "metadata": {"tool_names": list, "reminder"?: dict,
                                            "awaiting_clarification"?: bool}}
  {"type": "error",           "message": str}
Terminated by: "data: [DONE]\n\n"
"""

from __future__ import annotations

import asyncio
import json
import time
from collections.abc import AsyncGenerator
from datetime import datetime, timezone
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from fastapi.responses import StreamingResponse

from ..agents.system_prompts import get_system_prompt
from ..config.settings import settings
from ..lib.logger import logger
from ..lib.query_logger import log_query
from ..services.claude_client import ClaudeClient
from ..services.request_auth import resolve_user_id
from ..services.tool_executor import ToolExecutor
from ..services.user_aura_extractor import extract_and_update_user_aura


async def _get_user_local_datetime(uid: str) -> str:
    """Return 'Monday, 3 May 2026 14:32 IST' in the user's timezone, falling back to UTC."""
    from ..services.firebase import admin_firestore

    def _fetch() -> str | None:
        try:
            snap = admin_firestore().collection("users").document(uid).get()
            d = snap.to_dict()
            return d.get("timezone") if d else None
        except Exception:
            return None

    tz_str = await asyncio.to_thread(_fetch)
    try:
        tz = ZoneInfo(tz_str) if tz_str else timezone.utc
    except (ZoneInfoNotFoundError, Exception):
        tz = timezone.utc

    now = datetime.now(tz)
    return now.strftime("%A, %-d %B %Y %H:%M %Z")


def _resolve_user_id(event: dict[str, Any], body: dict[str, Any]) -> str | None:
    try:
        return event["requestContext"]["authorizer"]["jwt"]["claims"]["sub"]
    except (KeyError, TypeError):
        pass
    uid = body.get("user_id")
    explicit_uid = str(uid) if isinstance(uid, str) and uid else None
    return resolve_user_id(
        event.get("headers"),
        explicit_user_id=explicit_uid if not settings.is_production else None,
    )


def _error_stream(message: str) -> AsyncGenerator[str, None]:
    async def _gen():
        yield f"data: {json.dumps({'type': 'error', 'message': message})}\n\n"
        yield "data: [DONE]\n\n"

    return _gen()


def _sse_error_response(
    message: str,
    *,
    status_code: int,
    headers: dict[str, str],
) -> StreamingResponse:
    return StreamingResponse(
        _error_stream(message),
        media_type="text/event-stream",
        status_code=status_code,
        headers=headers,
    )


async def handle_chat_stream(event: dict[str, Any]) -> StreamingResponse:
    _sse_headers = {
        "Cache-Control": "no-cache",
        "X-Accel-Buffering": "no",
        "Connection": "keep-alive",
    }

    try:
        body: dict[str, Any] = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return _sse_error_response("Invalid JSON body", status_code=400, headers=_sse_headers)

    user_id = _resolve_user_id(event, body)
    if not user_id:
        logger.warn("Chat: rejected — missing user_id")
        return _sse_error_response(
            "Unauthorized: user_id required",
            status_code=401,
            headers=_sse_headers,
        )

    message = str(body.get("message", "")).strip()
    if not message:
        logger.warn("Chat: rejected — empty message", {"user_id": user_id})
        return _sse_error_response("message is required", status_code=400, headers=_sse_headers)
    if len(message) > 8_000:
        logger.warn(
            "Chat: rejected — message too long",
            {"user_id": user_id, "message_len": len(message)},
        )
        return _sse_error_response(
            "message must be 8 000 characters or fewer",
            status_code=400,
            headers=_sse_headers,
        )

    raw_session_id = body.get("session_id")
    session_id = (
        raw_session_id.strip()
        if isinstance(raw_session_id, str) and raw_session_id.strip()
        else None
    )

    raw_history: list[Any] = (body.get("history") or [])[-settings.CHAT_HISTORY_WINDOW * 2 :]
    history = [
        {"role": str(h.get("role", "")), "content": str(h.get("content", ""))}
        for h in raw_history
        if isinstance(h, dict) and h.get("role") in ("user", "assistant") and h.get("content")
    ][: settings.CHAT_HISTORY_WINDOW]

    client_message_id: str | None = body.get("client_message_id") or None
    agent_id: str | None = body.get("agent_id") or None

    # Build system prompt: datetime prefix + agent persona (if any) + default prompt
    datetime_line = f"Current date and time: {await _get_user_local_datetime(user_id)}"
    agent_prompt = get_system_prompt(agent_id) if agent_id else None
    effective_system_prompt = (
        f"{datetime_line}\n\n{agent_prompt}\n\n---\n\n{settings.BUDDY_CHAT_SYSTEM_PROMPT}"
        if agent_prompt
        else f"{datetime_line}\n\n{settings.BUDDY_CHAT_SYSTEM_PROMPT}"
    )

    await log_query(
        user_id,
        "chat",
        message,
        session_id=session_id,
        client_message_id=client_message_id,
    )
    asyncio.create_task(extract_and_update_user_aura(user_id, message))

    logger.info(
        "Chat: stream request received",
        {
            "user_id": user_id,
            "session_id": session_id,
            "agent_id": agent_id,
            "message_len": len(message),
            "history_turns": len(history),
        },
    )

    start_ts = time.monotonic()

    async def _generate() -> AsyncGenerator[str, None]:
        try:
            tool_executor = ToolExecutor(user_id)
            claude = ClaudeClient(tool_executor)
            async for sse_event in claude.send_text_turn_stream(
                system_prompt=effective_system_prompt,
                user_text=message,
                history=history,
                is_agent=bool(agent_id),
            ):
                yield f"data: {json.dumps(sse_event)}\n\n"
            duration_ms = int((time.monotonic() - start_ts) * 1000)
            logger.info(
                "Chat: stream complete",
                {
                    "user_id": user_id,
                    "duration_ms": duration_ms,
                },
            )
        except Exception as exc:
            duration_ms = int((time.monotonic() - start_ts) * 1000)
            logger.exception(
                "Chat: stream failed",
                {
                    "user_id": user_id,
                    "duration_ms": duration_ms,
                    "error": str(exc),
                    "error_type": type(exc).__name__,
                },
            )
            yield f"data: {json.dumps({'type': 'error', 'message': 'Internal server error'})}\n\n"
        finally:
            yield "data: [DONE]\n\n"

    return StreamingResponse(_generate(), media_type="text/event-stream", headers=_sse_headers)
