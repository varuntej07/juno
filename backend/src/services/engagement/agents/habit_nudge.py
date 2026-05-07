"""HabitNudgeAgent — calls out patterns in user behaviour (workout intent, sleep, etc.)."""

from __future__ import annotations

from ..models import NotificationOutput
from ...model_provider import ModelProvider
from .base_agent import BaseAgent


_SYSTEM_PROMPT = """You are Buddy. You pay attention to what the user does (and doesn't do).

Generate a push notification that calls out a behavioural pattern you've noticed.
Be specific — name the actual thing, don't be vague.
Sound like a friend who was listening, not an app reporting analytics.

Rules:
  - title: max 50 chars
  - body: max 100 chars — name the specific pattern
  - opening_chat_message: 1-2 sentences, opens a real conversation about it
  - suggested_replies: 2-3 chips
  - No "I noticed that..." opener — just say the thing
  - Be wry, not preachy

Return ONLY valid JSON:
{
  "title": "...",
  "body": "...",
  "opening_chat_message": "...",
  "suggested_replies": ["...", "...", "..."]
}"""


class HabitNudgeAgent(BaseAgent):
    def __init__(self, models: ModelProvider) -> None:
        super().__init__(models)

    async def generate(self, context: dict) -> NotificationOutput:
        signal: str = context.get("signal", "general")
        days_since: int = context.get("days_since", 0)
        query_count: int = context.get("query_count", 0)
        occurrences: int = context.get("occurrences", 0)

        if signal == "workout_intent_inactive":
            detail = (
                f"User asked about working out {query_count} times this week "
                f"but hasn't actually done it in {days_since} days."
            )
        elif signal == "late_night_sleep_concern":
            detail = (
                f"User asked about sleep/insomnia {occurrences} times between 11pm and 3am "
                f"this week."
            )
        else:
            detail = f"Signal: {signal}. Context: {context}"

        prompt = f"""Generate a habit nudge notification for this pattern:

{detail}

Be specific, wry, not preachy. Return JSON only."""

        return await self._models.cheap(
            prompt,
            system=_SYSTEM_PROMPT,
            response_model=NotificationOutput,
        )
