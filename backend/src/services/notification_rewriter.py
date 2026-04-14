"""
notification_rewriter.py: Rewrites reminder messages into engaging push notification copy.
"""

from __future__ import annotations

import anthropic
from anthropic.types import TextBlock

from ..config.settings import settings
from ..lib.logger import logger

_client: anthropic.AsyncAnthropic | None = None


def _get_client() -> anthropic.AsyncAnthropic:
    global _client
    if _client is None:
        _client = anthropic.AsyncAnthropic(api_key=settings.ANTHROPIC_API_KEY)
    return _client


_SYSTEM_PROMPT = """\
                You are Buddy, a sharp and witty personal AI assistant. Your job is to rewrite a reminder \
                into a punchy push notification that makes the user actually want to act on it.

                Rules:
                - Maximum 90 characters
                - Casual, direct, energetic tone with real personality
                - Match the vibe of the task: grind tasks get fired up energy, hygiene gets funny/playful, \
                  health gets encouraging and regular tasks get a sarcastic tone
                - Never use dashes anywhere in the output
                - No emojis
                - No quotes around the output
                - Do not use complex words or phrases which arent commonly used
                - Output only the rewritten notification text, nothing else
                """


async def rewrite_reminder_notification(message: str) -> str:
    """Rewrite a reminder message into engaging push notification copy """
    try:
        response = await _get_client().messages.create(
            model=settings.TIER_BALANCED,
            max_tokens=60,
            system=_SYSTEM_PROMPT,
            messages=[
                {"role": "user", "content": f"Reminder: {message}"},
            ],
        )
        block = response.content[0]
        if isinstance(block, TextBlock):
            rewritten = block.text.strip()
        else:
            rewritten = message
        logger.info("notification_rewriter: rewrote reminder", {
            "original_len": len(message),
            "rewritten_len": len(rewritten),
            "rewritten_preview": rewritten[:60],
        })
        return rewritten
    except Exception as exc:
        logger.warn("notification_rewriter: failed, using original message", {
            "error": str(exc),
        })
        return message
