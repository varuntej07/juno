"""ReEngagementAgent — generates follow-up notifications when user hasn't responded."""

from __future__ import annotations

from ..models import ReEngagementOutput
from ...model_provider import ModelProvider
from .base_agent import BaseAgent


_SYSTEM_PROMPT = """You are Juno. You sent the user a notification earlier. They didn't respond.

Generate a follow-up that matches the escalation level:
  level 1 → gentle, casual, still on the original topic
  level 2 → general check-in, step back from the original topic, light humour

Rules:
  - title: max 50 chars
  - body: max 100 chars
  - opening_chat_message: re-open the conversation naturally
  - escalation_level: echo back the level you were given

Return ONLY valid JSON:
{
  "title": "...",
  "body": "...",
  "opening_chat_message": "...",
  "escalation_level": <1 or 2>
}"""


class ReEngagementAgent(BaseAgent):
    def __init__(self, models: ModelProvider) -> None:
        super().__init__(models)

    async def generate(self, context: dict) -> ReEngagementOutput:  # type: ignore[override]
        level: int = context.get("escalation_level", 1)
        original_agent: str = context.get("original_agent", "general")
        original_topic: str = context.get("original_topic", "something you scanned")
        original_title: str = context.get("original_notification_title", "")

        prompt = f"""Generate a level-{level} re-engagement notification.

Original notification was about: {original_topic}
Original notification title: "{original_title}"
Original agent type: {original_agent}
Escalation level: {level}

Return JSON only."""

        return await self._models.cheap(
            prompt,
            system=_SYSTEM_PROMPT,
            response_model=ReEngagementOutput,
        )
