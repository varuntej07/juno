from __future__ import annotations
from pydantic import BaseModel


class NotificationContent(BaseModel):
    """Output from an agent's build_notification call."""
    title: str
    body: str
    chat_opener: str  # first message shown in the chat thread when user taps


class UserFeedback(BaseModel):
    """Recorded when a user interacts with a scheduled nudge."""
    nudge_id: str
    agent_id: str
    content_source: str
    content_topic: str
    user_action: str  # "tapped" | "skipped" | "snoozed" | "replied"
    user_reply: str | None = None
