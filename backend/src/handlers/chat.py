"""
POST /chat — text-based conversation via Claude with tool use.
Lambda-compatible response shape.
"""

from __future__ import annotations

import json
from typing import Any

from ..config.settings import settings
from ..lib.logger import logger
from ..services.claude_client import ClaudeClient
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
    # Explicit body field (dev/testing)
    uid = body.get("user_id")
    return str(uid) if isinstance(uid, str) and uid else None


async def handle_chat_request(event: dict[str, Any]) -> dict[str, Any]:
    try:
        body: dict[str, Any] = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return _json(400, {"error": "Invalid JSON body"})

    user_id = _resolve_user_id(event, body)
    if not user_id:
        return _json(401, {"error": "Unauthorized: user_id required"})

    message = str(body.get("message", "")).strip()
    if not message:
        return _json(400, {"error": "message is required"})

    try:
        tool_executor = ToolExecutor(user_id)
        claude = ClaudeClient(tool_executor)

        # Build context-aware system prompt
        context = await tool_executor.execute("get_user_context", {})
        system_prompt = (
            f"{settings.JUNO_DEFAULT_SYSTEM_PROMPT}\n\n"
            f"User context:\n{json.dumps(context, indent=2)}"
        )

        result = await claude.send_text_turn(
            system_prompt=system_prompt,
            user_text=message,
        )

        return _json(200, {
            "text": result["text"],
            "intent": "assistant_response",
            "metadata": {"tool_names": result["tool_names"]},
        })

    except Exception as exc:
        logger.error("Chat request failed", {"error": str(exc), "user_id": user_id})
        return _json(500, {"error": "Internal server error"})
