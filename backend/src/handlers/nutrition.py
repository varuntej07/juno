"""POST /nutrition/analyze — OCR nutrition label analysis."""

from __future__ import annotations

import json
from typing import Any

from ..lib.logger import logger
from ..services.tool_executor import ToolExecutor


def _json(status: int, payload: dict[str, Any]) -> dict[str, Any]:
    return {
        "statusCode": status,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(payload),
    }


def _resolve_user_id(event: dict[str, Any], body: dict[str, Any]) -> str | None:
    try:
        return event["requestContext"]["authorizer"]["jwt"]["claims"]["sub"]
    except (KeyError, TypeError):
        pass
    uid = body.get("user_id")
    return str(uid) if isinstance(uid, str) and uid else None


async def handle_nutrition_analyze_request(event: dict[str, Any]) -> dict[str, Any]:
    try:
        body: dict[str, Any] = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return _json(400, {"error": "Invalid JSON body"})

    user_id = _resolve_user_id(event, body)
    if not user_id:
        return _json(401, {"error": "Unauthorized: user_id required"})

    ocr_text = str(body.get("ocr_text", "")).strip()
    if not ocr_text:
        return _json(400, {"error": "ocr_text is required"})

    try:
        tool_executor = ToolExecutor(user_id)
        result = await tool_executor.execute("analyze_nutrition", body)
        return _json(200, result)
    except Exception as exc:
        logger.error("Nutrition analyze failed", {"error": str(exc), "user_id": user_id})
        return _json(500, {"error": "Internal server error"})
