from __future__ import annotations

from typing import Any

from ...services.model_provider import ModelProvider
from ..agent_base import ScheduledAgent
from ..data_fetchers.hackernews import fetch_top_stories
from ..data_fetchers.arxiv_papers import fetch_recent_papers


class TechNewsAgent(ScheduledAgent):
    """
    BytePulse — surfaces top HN stories + fresh arXiv papers.
    Tone: sharp, no-hype tech lens. Flags what matters, skips the noise.
    """

    def __init__(self, models: ModelProvider) -> None:
        self._models = models

    @property
    def agent_id(self) -> str:
        return "technews"

    async def fetch_data(self, user_config: dict[str, Any]) -> list[dict[str, Any]]:
        categories = user_config.get("arxiv_categories", ["cs.LG", "cs.AI"])
        hn_stories, papers = await __import__("asyncio").gather(
            fetch_top_stories(limit=8),
            fetch_recent_papers(categories=categories, max_results=5),
        )
        return [*hn_stories, *papers]

    async def build_notification(
        self,
        content: list[dict[str, Any]],
        user_config: dict[str, Any],
        recent_feedback: list[dict[str, Any]],
    ) -> dict[str, str]:
        if not content:
            return {
                "title": "BytePulse",
                "body": "Feed is quiet today. Check back later.",
                "chat_opener": "Nothing major dropped today — want me to search a specific topic?",
            }

        interests = user_config.get("interests", ["AI", "ML", "startups"])
        engagement_summary = _summarize_feedback(recent_feedback)

        prompt = f"""You are BytePulse, a sharp tech analyst who cuts through hype.

User's interests: {', '.join(interests)}
Recent engagement: {engagement_summary}

Latest tech content:
{_format_content(content)}

Generate a push notification with this JSON structure:
{{
  "title": "<max 50 chars, punchy>",
  "body": "<max 100 chars, specific — name the actual story or paper>",
  "chat_opener": "<1-2 sentences to kick off a tech conversation, no fluff>"
}}

Rules:
- Name the actual story, paper, or company — no generic filler
- If there's a genuinely surprising or important story, lead with that
- Match interests when possible
- Return ONLY valid JSON, no markdown.
"""
        result = await self._models.fast(
            prompt,
            system="You are BytePulse, a sharp tech analyst. Output valid JSON only.",
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
    for item in content[:8]:
        source = item.get("source", "")
        if source == "hackernews":
            score = item.get("score", "")
            score_str = f" ({score} pts)" if score else ""
            lines.append(f"HN: {item.get('title', '')}{score_str}")
        elif source == "arxiv":
            lines.append(f"arXiv: {item.get('title', '')} — {item.get('summary', '')[:120]}")
        else:
            lines.append(f"- {item.get('title', item.get('headline', ''))}")
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
            "title": "BytePulse",
            "body": "Big things are moving in tech. Tap to catch up.",
            "chat_opener": "Got some interesting tech stories — want the highlights?",
        }
