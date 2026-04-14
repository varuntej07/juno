"""
NutritionFollowupAgent — generates post-scan engagement notifications.

Uses ModelProvider.fast() (Gemini Flash) — copy generation needs no heavy reasoning.

Tone mapping (set by DecisionEngine, not by this agent):
    educate   → first time eating this food
    warn      → seen before, bad-ish verdict (1–2 prior scans)
    roast     → same bad food 3+ times
    celebrate → good choice, on track with goals
"""

from __future__ import annotations

import json

from ..models import NotificationOutput
from ...model_provider import ModelProvider
from .base_agent import BaseAgent


_SYSTEM_PROMPT = """You are Juno, a brutally honest health companion.
Think: that one friend who read the label before you did.

Generate a push notification about a food the user just scanned.
Tone is specified in the context — follow it exactly.

tone options:
  educate   → user never had this food; explain what it is + key concern
  warn      → user has had it before; they know the deal, remind them firmly
  roast     → user keeps eating it despite your warnings; call them out, be funny
  celebrate → great choice; be genuinely pleased but not corporate

Rules:
  - title: max 50 chars, punchy, no corporate speak
  - body: max 100 chars, the real talk
  - initial_chat_message: 1-2 sentences, sounds like picking up a conversation
  - suggested_replies: 2-3 short tappable chips the user can reply with
  - No "Great choice!" or "As an AI..." — be a friend, not an app
  - Mild profanity is okay if tone is roast

Return ONLY valid JSON, no markdown fences:
{
  "title": "...",
  "body": "...",
  "initial_chat_message": "...",
  "suggested_replies": ["...", "...", "..."]
}"""


class NutritionFollowupAgent(BaseAgent):
    def __init__(self, models: ModelProvider) -> None:
        super().__init__(models)

    async def generate(self, context: dict) -> NotificationOutput:
        tone: str = context.get("tone", "educate")
        food_name: str = context.get("food_name", "that food")
        first_time: bool = context.get("first_time", True)
        past_count: int = context.get("past_scan_count", 0)
        concerns: list = context.get("concerns", [])
        verdict: str = context.get("verdict", "moderate")
        macros: dict = context.get("macros", {})
        dietary_goal: str = context.get("dietary_goal", "")
        restrictions: list = context.get("restrictions", [])

        prompt = f"""Generate a push notification for this nutrition scan.

Food: {food_name}
Tone to use: {tone}
First time scanning this food: {first_time}
Times scanned before: {past_count}
Verdict: {verdict}
Concerns: {", ".join(concerns) or "none"}
Key macros: {json.dumps(macros)}
User's dietary goal: {dietary_goal or "not set"}
Dietary restrictions: {", ".join(restrictions) or "none"}

Remember: follow the tone exactly. Return JSON only."""

        return await self._models.fast(
            prompt,
            system=_SYSTEM_PROMPT,
            response_model=NotificationOutput,
        )
