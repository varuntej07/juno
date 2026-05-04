from __future__ import annotations

from typing import Any

from ...services.model_provider import ModelProvider
from ..agent_base import ScheduledAgent
from ..data_fetchers.cricket_scores import fetch_recent_results, fetch_live_matches


class CricketAgent(ScheduledAgent):
    """
    CricBolt — delivers cricket scores, match results, and live match alerts.
    Tone: witty cricket pundit. Knows CSK, RCB, and whatever teams the user follows.
    """

    def __init__(self, models: ModelProvider) -> None:
        self._models = models

    @property
    def agent_id(self) -> str:
        return "cricket"

    async def fetch_data(self, user_config: dict[str, Any]) -> list[dict[str, Any]]:
        results, live = await __import__("asyncio").gather(
            fetch_recent_results(limit=5),
            fetch_live_matches(),
        )
        return [*live, *results]

    async def build_notification(
        self,
        content: list[dict[str, Any]],
        user_config: dict[str, Any],
        recent_feedback: list[dict[str, Any]],
    ) -> dict[str, str]:
        if not content:
            return {
                "title": "CricBolt",
                "body": "Nothing on the pitch today. Check back later.",
                "chat_opener": "No live matches right now — want me to look up the schedule?",
            }

        teams = user_config.get("teams", ["CSK", "RCB", "India"])
        engagement_summary = _summarize_feedback(recent_feedback)

        prompt = f"""You are CricBolt, a witty cricket analyst.

Favorite teams: {', '.join(teams)}
Recent user engagement: {engagement_summary}

Latest cricket news / scores:
{_format_content(content)}

Generate a push notification with this JSON structure:
{{
  "title": "<max 50 chars, punchy>",
  "body": "<max 100 chars, witty or informative>",
  "chat_opener": "<1-2 sentences to start the chat thread, cricket voice>"
}}

Rules:
- If a user's favorite team won, be celebratory
- If they lost, be wry but not mean
- No generic filler. Every word earns its place.
- Return ONLY valid JSON, no markdown.
"""
        result = await self._models.fast(
            prompt,
            system="You are CricBolt, a sharp cricket analyst. Output valid JSON only.",
        )
        return _parse_notification_json(result)


def _summarize_feedback(recent: list[dict]) -> str:
    if not recent:
        return "No history yet"
    tapped = sum(1 for r in recent if r.get("user_action") == "tapped")
    total = len(recent)
    return f"{tapped}/{total} recent nudges engaged with"


def _format_content(content: list[dict]) -> str:
    lines = []
    for item in content[:5]:
        if item.get("source") == "cricbuzz":
            lines.append(f"LIVE: {item.get('team1')} vs {item.get('team2')} — {item.get('score')}")
        else:
            lines.append(f"- {item.get('headline', item.get('title', ''))}")
    return "\n".join(lines) or "No content"


def _parse_notification_json(raw: Any) -> dict[str, str]:
    import json
    try:
        if isinstance(raw, dict):
            return raw
        text = str(raw).strip()
        if text.startswith("```"):
            text = text.split("```")[1].lstrip("json").strip()
        return json.loads(text)
    except Exception:
        return {
            "title": "CricBolt",
            "body": "Cricket news is in. Tap to catch up.",
            "chat_opener": "Got some cricket updates for you — want the highlights?",
        }
