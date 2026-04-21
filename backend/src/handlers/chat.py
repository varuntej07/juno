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

import json
import time
from typing import Any, AsyncGenerator

from fastapi.responses import StreamingResponse

from ..config.settings import settings
from ..lib.logger import logger
from ..lib.query_logger import log_query
from ..services.claude_client import ClaudeClient
from ..services.request_auth import resolve_user_id
from ..services.tool_executor import ToolExecutor


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


async def handle_chat_stream(event: dict[str, Any]) -> StreamingResponse:
    _sse_headers = {
        "Cache-Control": "no-cache",
        "X-Accel-Buffering": "no",
        "Connection": "keep-alive",
    }

    try:
        body: dict[str, Any] = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return StreamingResponse(_error_stream("Invalid JSON body"), media_type="text/event-stream", status_code=400, headers=_sse_headers)

    user_id = _resolve_user_id(event, body)
    if not user_id:
        logger.warn("Chat: rejected — missing user_id")
        return StreamingResponse(_error_stream("Unauthorized: user_id required"), media_type="text/event-stream", status_code=401, headers=_sse_headers)

    message = str(body.get("message", "")).strip()
    if not message:
        logger.warn("Chat: rejected — empty message", {"user_id": user_id})
        return StreamingResponse(_error_stream("message is required"), media_type="text/event-stream", status_code=400, headers=_sse_headers)
    if len(message) > 8_000:
        logger.warn("Chat: rejected — message too long", {"user_id": user_id, "message_len": len(message)})
        return StreamingResponse(_error_stream("message must be 8 000 characters or fewer"), media_type="text/event-stream", status_code=400, headers=_sse_headers)

    raw_session_id = body.get("session_id")
    session_id = raw_session_id.strip() if isinstance(raw_session_id, str) and raw_session_id.strip() else None

    raw_history: list[Any] = (body.get("history") or [])[-settings.CHAT_HISTORY_WINDOW * 2:]
    history = [
        {"role": str(h.get("role", "")), "content": str(h.get("content", ""))}
        for h in raw_history
        if isinstance(h, dict) and h.get("role") in ("user", "assistant") and h.get("content")
    ][:settings.CHAT_HISTORY_WINDOW]

    client_message_id: str | None = body.get("client_message_id") or None

    await log_query(user_id, "chat", message, session_id=session_id, client_message_id=client_message_id)

    logger.info("Chat: stream request received", {
        "user_id": user_id,
        "session_id": session_id,
        "message_len": len(message),
        "message_preview": message[:80],
        "history_turns": len(history),
    })

    start_ts = time.monotonic()

    async def _generate() -> AsyncGenerator[str, None]:
        try:
            tool_executor = ToolExecutor(user_id)
            claude = ClaudeClient(tool_executor)
            async for sse_event in claude.send_text_turn_stream(
                system_prompt=settings.JUNO_DEFAULT_SYSTEM_PROMPT,
                user_text=message,
                history=history,
            ):
                yield f"data: {json.dumps(sse_event)}\n\n"
            duration_ms = int((time.monotonic() - start_ts) * 1000)
            logger.info("Chat: stream complete", {
                "user_id": user_id,
                "duration_ms": duration_ms,
            })
        except Exception as exc:
            duration_ms = int((time.monotonic() - start_ts) * 1000)
            logger.exception("Chat: stream failed", {
                "user_id": user_id,
                "duration_ms": duration_ms,
                "error": str(exc),
                "error_type": type(exc).__name__,
            })
            yield f"data: {json.dumps({'type': 'error', 'message': 'Internal server error'})}\n\n"
        finally:
            yield "data: [DONE]\n\n"

    return StreamingResponse(_generate(), media_type="text/event-stream", headers=_sse_headers)
