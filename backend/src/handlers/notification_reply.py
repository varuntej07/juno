"""POST /notification-reply — user replied to a push notification; route to chat."""

from __future__ import annotations

from typing import Any

from .chat import handle_chat_request


async def handle_notification_reply_request(event: dict[str, Any]) -> dict[str, Any]:
    return await handle_chat_request(event)
