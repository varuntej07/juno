"""
POST /chat — text-based conversation via Claude with tool use.
Lambda-compatible response shape.
"""

from __future__ import annotations

import json
import time
from typing import Any

from ..config.settings import settings
from ..lib.logger import logger
from ..services.claude_client import ClaudeClient
from ..services.request_auth import resolve_user_id
from ..services.tool_executor import ToolExecutor


def _json(status: int, payload: dict[str, Any]) -> dict[str, Any]:
    return {
        "statusCode": status,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(payload),
    }


def _resolve_user_id(event: dict[str, Any], body: dict[str, Any]) -> str | None:
    # API Gateway JWT authorizer
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


async def handle_chat_request(event: dict[str, Any]) -> dict[str, Any]:
    start_ts = time.monotonic()

    try:
        body: dict[str, Any] = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return _json(400, {"error": "Invalid JSON body"})

    user_id = _resolve_user_id(event, body)
    if not user_id:
        logger.warn("Chat: rejected — missing user_id")
        return _json(401, {"error": "Unauthorized: user_id required"})

    message = str(body.get("message", "")).strip()
    if not message:
        logger.warn("Chat: rejected — empty message", {"user_id": user_id})
        return _json(400, {"error": "message is required"})

    # Optional conversation history: [{role: "user"|"assistant", content: str}]
    # Capped server-side so a misbehaving client cannot blow the token budget.
    raw_history: list[Any] = body.get("history") or []
    history = [
        {"role": str(h.get("role", "")), "content": str(h.get("content", ""))}
        for h in raw_history
        if isinstance(h, dict)
           and h.get("role") in ("user", "assistant")
           and h.get("content")
    ][: settings.CHAT_HISTORY_WINDOW]

    logger.info("Chat: request received", {
        "user_id": user_id,
        "message_len": len(message),
        "message_preview": message[:80],
        "history_turns": len(history),
    })

    try:
        tool_executor = ToolExecutor(user_id)
        claude = ClaudeClient(tool_executor)

        result = await claude.send_text_turn(
            system_prompt=settings.JUNO_DEFAULT_SYSTEM_PROMPT,
            user_text=message,
            history=history,
        )

        duration_ms = int((time.monotonic() - start_ts) * 1000)
        logger.info("Chat: request completed", {
            "user_id": user_id,
            "duration_ms": duration_ms,
            "response_len": len(result["text"]),
            "tools_used": result["tool_names"],
            "response_preview": result["text"][:100],
        })

        return _json(200, {
            "text": result["text"],
            "intent": "assistant_response",
            "metadata": {"tool_names": result["tool_names"]},
        })

    except Exception as exc:
        duration_ms = int((time.monotonic() - start_ts) * 1000)
        logger.exception("Chat: request failed", {
            "user_id": user_id,
            "duration_ms": duration_ms,
            "error": str(exc),
            "error_type": type(exc).__name__,
        })
        return _json(500, {"error": "Internal server error"})
