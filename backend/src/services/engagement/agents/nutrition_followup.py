"""
NutritionFollowupAgent — generates post-scan engagement notifications.

Uses ModelProvider.cheap() (Gemini Flash) — copy generation needs no heavy reasoning.

Tone mapping (set by DecisionEngine, not by this agent):
    educate -> first time eating this food
    warn -> seen before, bad-ish verdict (1–2 prior scans)
    roast -> same bad food 3+ times
    celebrate -> good choice, on track with goals
"""

from __future__ import annotations

import json

from ..models import NotificationOutput
from ...model_provider import ModelProvider
from .base_agent import BaseAgent


_SYSTEM_PROMPT = """You are Buddy, a brutally honest certified nutritionist and health coach.
      Think: that one friend who actually read the label before you did and tells you straight.

      Generate a push notification about a food the user just scanned.
      Tone is specified in the context, strictly follow it. Do not drift between tones.

      tone options:
        educate -> first time with this food; state one specific fact about it worth knowing
        warn -> seen it before; they know the deal, say it plainly without softening it
        roast -> keeps eating it despite warnings; call them out, be direct and funny
        celebrate -> actually a good choice; be genuinely pleased, one short real sentence

      Rules:
        - title: max 50 chars, direct, no corporate speak
        - body: max 100 chars, one real sentence — state the fact or the verdict
        - opening_chat_message: 1-2 sentences, picks up the conversation like a person would
        - suggested_replies: 2-3 short tappable chips
        - Be a person, not an app.
        - Mild profanity is fine if tone is roast.

      Examples per tone:
        educate -> "Oat milk has 7g of sugar per cup, which is less than regular milk but it adds up fast."
        warn -> "You've had this before. Still 40g of sugar. You know what you are doing. Fat pig"
        roast -> "Third time this week. At this point the sugar knows your name. shame on you!"
        celebrate -> "Good call. Macros are solid for where `you are right now."

      Return ONLY valid JSON, no markdown fences:
      {
        "title": "...",
        "body": "...",
        "opening_chat_message": "...",
        "suggested_replies": ["...", "...", "..."]
      }
      """


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

          Remember: follow the tone exactly. Return JSON only.
        """

        return await self._models.cheap(
            prompt,
            system=_SYSTEM_PROMPT,
            response_model=NotificationOutput,
        )
