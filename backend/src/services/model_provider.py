"""
ModelProvider — unified LLM interface with tier-based routing.

Usage:
    provider = ModelProvider()

    # Cheap + fast (Gemini Flash) — notification copy, classification, summaries
    text = await provider.fast("Write a punchy notification about sardines")

    # Mid-tier (Claude Haiku) — tool-calling tasks, structured output with reasoning
    result = await provider.balanced("Classify this query", response_model=MyModel)

    # Best reasoning (Claude Sonnet) — main chat, complex multi-turn
    result = await provider.smart("...", tools=[...], history=[...])

Model IDs come from settings.TIER_FAST / TIER_BALANCED / TIER_SMART.
To upgrade a tier: change ONE line in settings.py — zero call-site changes.

Provider routing is inferred from the model ID prefix:
    "gemini-*"  → Google Gen AI SDK
    "claude-*"  → Anthropic SDK
    (future) "gpt-*" → OpenAI SDK, "sonar-*" → Perplexity SDK
"""

from __future__ import annotations

import asyncio
import re
from typing import Any, TypeVar, Type

import anthropic

from ..config.settings import settings
from ..lib.logger import logger

T = TypeVar("T")

# Model ID prefix → provider name
_PROVIDER_PREFIXES: dict[str, str] = {
    "gemini":  "gemini",
    "claude":  "anthropic",
    "gpt":     "openai",       # future
    "sonar":   "perplexity",   # future
    "o1":      "openai",       # future
    "o3":      "openai",       # future
}


def _infer_provider(model_id: str) -> str:
    for prefix, provider in _PROVIDER_PREFIXES.items():
        if model_id.startswith(prefix):
            return provider
    raise ValueError(
        f"ModelProvider: cannot infer provider for model '{model_id}'. "
        f"Add its prefix to _PROVIDER_PREFIXES in model_provider.py."
    )


def _strip_fences(text: str) -> str:
    text = re.sub(r"^```(?:json)?\s*", "", text, flags=re.MULTILINE)
    text = re.sub(r"\s*```$", "", text, flags=re.MULTILINE)
    return text.strip()


class ModelProvider:
    """
    Tier-based LLM interface. Three tiers, any number of underlying models.

    fast()     → settings.TIER_FAST     (currently gemini-2.5-flash)
    balanced() → settings.TIER_BALANCED (currently claude-haiku-4-5)
    smart()    → settings.TIER_SMART    (currently claude-sonnet-4-6)

    When response_model (a Pydantic BaseModel subclass) is given, the raw LLM
    text is parsed as JSON into that model and returned as the typed instance.
    Otherwise, the raw string is returned.
    """

    def __init__(self) -> None:
        self._anthropic: anthropic.AsyncAnthropic | None = None
        self._gemini_client: Any = None   # google.genai.Client, lazy

    # ── Tier methods ──────────────────────────────────────────────────────────

    async def fast(
        self,
        prompt: str,
        *,
        system: str | None = None,
        response_model: Type[T] | None = None,
        temperature: float = 0.7,
    ) -> str | T:
        """Cheap and fast. Use for: notification copy, summaries, classification.
        Currently routes to Gemini Flash via TIER_FAST setting."""
        model_id = settings.TIER_FAST
        logger.debug("ModelProvider.fast", {"model": model_id, "prompt_len": len(prompt)})
        return await self._call(
            model_id=model_id,
            prompt=prompt,
            system=system,
            response_model=response_model,
            temperature=temperature,
        )

    async def balanced(
        self,
        prompt: str,
        *,
        system: str | None = None,
        tools: list[dict] | None = None,
        response_model: Type[T] | None = None,
        temperature: float = 0.5,
    ) -> str | T:
        """Mid-tier reasoning. Use for: tool-calling background tasks, structured
        output that needs mild reasoning. Currently routes to Claude Haiku."""
        model_id = settings.TIER_BALANCED
        logger.debug("ModelProvider.balanced", {"model": model_id, "prompt_len": len(prompt)})
        return await self._call(
            model_id=model_id,
            prompt=prompt,
            system=system,
            tools=tools,
            response_model=response_model,
            temperature=temperature,
        )

    async def smart(
        self,
        prompt: str,
        *,
        system: str | None = None,
        tools: list[dict] | None = None,
        history: list[dict] | None = None,
        response_model: Type[T] | None = None,
        temperature: float = 0.7,
    ) -> str | T:
        """Best reasoning. Use for: main chat, complex multi-turn, high-stakes output.
        Most expensive — only use where quality matters. Currently Claude Sonnet."""
        model_id = settings.TIER_SMART
        logger.debug("ModelProvider.smart", {"model": model_id, "prompt_len": len(prompt)})
        return await self._call(
            model_id=model_id,
            prompt=prompt,
            system=system,
            tools=tools,
            history=history,
            response_model=response_model,
            temperature=temperature,
        )

    # ── Internal dispatch ─────────────────────────────────────────────────────

    async def _call(
        self,
        *,
        model_id: str,
        prompt: str,
        system: str | None,
        tools: list[dict] | None = None,
        history: list[dict] | None = None,
        response_model: Type[T] | None,
        temperature: float,
    ) -> str | T:
        provider = _infer_provider(model_id)

        if provider == "gemini":
            raw = await self._call_gemini(
                model_id=model_id,
                prompt=prompt,
                system=system,
                temperature=temperature,
            )
        elif provider == "anthropic":
            raw = await self._call_anthropic(
                model_id=model_id,
                prompt=prompt,
                system=system,
                tools=tools,
                history=history,
                temperature=temperature,
            )
        else:
            raise NotImplementedError(
                f"ModelProvider: provider '{provider}' is not yet implemented. "
                f"Add a _call_{provider}() method to model_provider.py."
            )

        if response_model is not None:
            return self._parse_response(raw, response_model)
        return raw

    # ── Provider implementations ──────────────────────────────────────────────

    async def _call_gemini(
        self,
        *,
        model_id: str,
        prompt: str,
        system: str | None,
        temperature: float,
    ) -> str:
        client = self._get_gemini_client()
        from google.genai import types  # type: ignore

        contents: list = []
        if system:
            # Gemini: system instruction goes in GenerateContentConfig, not contents
            config = types.GenerateContentConfig(
                system_instruction=system,
                temperature=temperature,
                max_output_tokens=1024,
            )
        else:
            config = types.GenerateContentConfig(
                temperature=temperature,
                max_output_tokens=1024,
            )

        contents.append(prompt)

        def _sync() -> str:
            resp = client.models.generate_content(
                model=model_id,
                contents=contents,
                config=config,
            )
            return resp.text or ""

        return await asyncio.to_thread(_sync)

    async def _call_anthropic(
        self,
        *,
        model_id: str,
        prompt: str,
        system: str | None,
        tools: list[dict] | None,
        history: list[dict] | None,
        temperature: float,
    ) -> str:
        client = self._get_anthropic_client()

        messages: list[dict] = []
        if history:
            messages.extend(history)
        messages.append({"role": "user", "content": prompt})

        kwargs: dict[str, Any] = {
            "model": model_id,
            "max_tokens": 1024,
            "messages": messages,
            "temperature": temperature,
        }
        if system:
            kwargs["system"] = system
        if tools:
            kwargs["tools"] = tools

        response = await client.messages.create(**kwargs)

        text_blocks = [b.text for b in response.content if b.type == "text"]
        return " ".join(text_blocks).strip()

    # ── Response parsing ──────────────────────────────────────────────────────

    def _parse_response(self, raw: str, response_model: Type[T]) -> T:
        """Parse raw LLM text into a Pydantic model. Strips markdown fences."""
        cleaned = _strip_fences(raw)
        try:
            return response_model.model_validate_json(cleaned)  # type: ignore[attr-defined]
        except Exception as exc:
            logger.error("ModelProvider: failed to parse LLM response", {
                "model": response_model.__name__,
                "error": str(exc),
                "raw_preview": cleaned[:200],
            })
            raise ValueError(
                f"ModelProvider: could not parse response into {response_model.__name__}: {exc}"
            ) from exc

    # ── Lazy client accessors ─────────────────────────────────────────────────

    def _get_anthropic_client(self) -> anthropic.AsyncAnthropic:
        if self._anthropic is None:
            self._anthropic = anthropic.AsyncAnthropic(api_key=settings.ANTHROPIC_API_KEY)
        return self._anthropic

    def _get_gemini_client(self) -> Any:
        if self._gemini_client is None:
            if not settings.GEMINI_API_KEY:
                raise ValueError("GEMINI_API_KEY is not set — fast() tier unavailable")
            from google import genai  # type: ignore
            self._gemini_client = genai.Client(api_key=settings.GEMINI_API_KEY)
        return self._gemini_client


# ── Module-level singleton (same pattern as firebase.py) ─────────────────────

_provider: ModelProvider | None = None


def get_model_provider() -> ModelProvider:
    """Return the shared ModelProvider singleton. Thread-safe for read access."""
    global _provider
    if _provider is None:
        _provider = ModelProvider()
    return _provider
