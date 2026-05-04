"""Web search via Gemini 2.0 Flash with google_search grounding."""

from __future__ import annotations

import asyncio

from ...config.settings import settings
from ...lib.logger import logger

def _search_sync(query: str, uid: str) -> str:
    if not settings.GEMINI_API_KEY:
        raise ValueError("GEMINI_API_KEY not configured — web search unavailable")

    from google import genai  # type: ignore
    from google.genai import types  # type: ignore

    client = genai.Client(api_key=settings.GEMINI_API_KEY)
    tool = types.Tool(google_search=types.GoogleSearch())
    config = types.GenerateContentConfig(tools=[tool], temperature=1.0)

    response = client.models.generate_content(
        model=settings.GEMINI_MODEL,
        contents=query,
        config=config,
    )
    text = response.text or ""
    logger.info("web_search OK", {"uid": uid, "query_len": len(query), "result_len": len(text)})
    return text


async def web_search(query: str, uid: str) -> str:
    """Call Gemini 2.0 Flash with google_search grounding and return the response text."""
    try:
        return await asyncio.to_thread(_search_sync, query, uid)
    except Exception as exc:
        logger.error("web_search failed", {"uid": uid, "query": query, "error": str(exc)})
        raise
