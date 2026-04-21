"""
notification_rewriter.py: Rewrites reminder messages into engaging push notification copy.
"""

from __future__ import annotations

import asyncio
import random

import anthropic
from anthropic.types import TextBlock
from langsmith import traceable
from langsmith.wrappers import wrap_anthropic

from ..config.settings import settings
from ..lib.logger import logger

_MAX_RETRIES = 2
_BASE_DELAY_S = 1.0  # exponential backoff: 1s, 2s
_TIMEOUT_S = 15.0    # short budget; notification copy is non-critical

# Anthropic exceptions that are worth retrying (transient / server-side)
_RETRYABLE_ERRORS = (
    anthropic.RateLimitError,        # 429
    anthropic.APIConnectionError,    # network blip (includes APITimeoutError)
    anthropic.InternalServerError,   # 500 / 529
)

_client: anthropic.AsyncAnthropic | None = None


def _get_client() -> anthropic.AsyncAnthropic:
    global _client
    if _client is None:
        _client = wrap_anthropic(anthropic.AsyncAnthropic(
            api_key=settings.ANTHROPIC_API_KEY,
            timeout=_TIMEOUT_S,
        ))
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


@traceable(name="notification_rewrite", run_type="llm")
async def rewrite_reminder_notification(message: str) -> str:
    """Rewrite a reminder message into engaging push notification copy """
    for attempt in range(1, _MAX_RETRIES + 1):
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
                "model": settings.TIER_BALANCED,
                "original_len": len(message),
                "rewritten_len": len(rewritten),
                "rewritten_preview": rewritten[:60],
                "attempt": attempt,
            })
            return rewritten
        except _RETRYABLE_ERRORS as exc:
            if attempt == _MAX_RETRIES:
                logger.warn("notification_rewriter: retries exhausted, using original message", {
                    "model": settings.TIER_BALANCED,
                    "attempt": attempt,
                    "error_type": type(exc).__name__,
                    "error": str(exc),
                })
                return message
            delay = _BASE_DELAY_S * (2 ** (attempt - 1)) + random.uniform(0, 0.5)
            logger.warn("notification_rewriter: retryable error, backing off", {
                "model": settings.TIER_BALANCED,
                "attempt": attempt,
                "delay_s": round(delay, 2),
                "error_type": type(exc).__name__,
                "error": str(exc),
            })
            await asyncio.sleep(delay)
        except Exception as exc:
            logger.warn("notification_rewriter: failed, using original message", {
                "model": settings.TIER_BALANCED,
                "error_type": type(exc).__name__,
                "error": str(exc),
            })
            return message
    return message
