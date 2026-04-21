"""POST /notification-reply — user replied to a push notification; route to chat."""

from __future__ import annotations

from typing import Any

from fastapi.responses import StreamingResponse

from .chat import handle_chat_stream


async def handle_notification_reply_request(event: dict[str, Any]) -> StreamingResponse:
    return await handle_chat_stream(event)
