"""
Gemini client via Google Gen AI SDK (google-genai).

Uses the Gemini Developer API with an API key (GEMINI_API_KEY).
Model: gemini-2.5-pro for nutrition scan + analyze — best-in-class vision and
reasoning for a quality-critical user-facing feature.

Two public async methods:
  - scan_image() -> detect food + return consumption-context clarifying questions
  - analyze_food() -> full macro + verdict + pros/cons given answers + dietary profile
"""

from __future__ import annotations

import asyncio
import json
import random
import re
import time
import uuid
from dataclasses import dataclass, field
from typing import Any

from ..config.settings import settings
from ..lib.logger import logger

_MAX_RETRIES = 3
_BASE_DELAY_S = 1.0  # exponential backoff: 1s, 2s, 4s


# Data classes returned to callers

@dataclass
class ScanQuestion:
    id: str
    text: str
    input_type: str   # "select" | "text" | "number" | "boolean"
    options: list[str] = field(default_factory=list)


@dataclass
class ScanResult:
    scan_id: str
    detected_type: str          # "nutrition_label" | "restaurant_food" | "packaged_food" | "unknown"
    detected_items: list[str]
    confidence: float
    raw_text: str               # extracted label text when detected_type == "nutrition_label"
    clarifying_questions: list[ScanQuestion]
    needs_clarification: bool
    food_category: str          # "fast food" | "grain" | "snack" | "protein" | etc.


@dataclass
class AnalysisResult:
    food_name: str
    headline: str               # Buddy's one-liner gut reaction (8–14 words, friend-voice)
    macros: dict[str, float]    # calories, protein_g, carbs_g, fat_g, sugar_g, sodium_mg, fiber_g
    key_nutrients: list[dict]   # [{name, value, context, sentiment}] — only the ones that matter
    recommendation: str         # "eat" | "moderate" | "skip"
    verdict_reason: str
    concerns: list[str]
    pros: list[str]             # personalized benefits given user goal + answers
    cons: list[str]             # personalized drawbacks given user goal + answers


# Prompts

_SCAN_SYSTEM = """You are a precision nutrition coach with expert-level food recognition. Analyze the image and return ONLY valid JSON — no markdown, no prose.

Identify the food precisely. Then generate smart, food-specific questions about the user's CONSUMPTION INTENT — not about the image clarity. You already see the image clearly; your questions help personalize the nutrition analysis.

Return this exact JSON structure:
{{
  "detected_type": "nutrition_label" | "restaurant_food" | "packaged_food" | "unknown",
  "detected_items": ["<specific item name>"],
  "food_category": "<one of: fast food | grain | dairy | protein | snack | beverage | fruit | vegetable | restaurant | dessert | processed>",
  "confidence": <0.0–1.0>,
  "raw_text": "<full extracted text if nutrition_label, else empty string>",
  "clarifying_questions": [
    {{
      "id": "q1",
      "text": "<specific, conversational question — max 12 words>",
      "input_type": "select" | "boolean" | "number",
      "options": ["<short option 1>", "<short option 2>", "<short option 3>"]
    }}
  ]
}}

Question generation rules:
- detected_type == "nutrition_label" AND confidence >= {threshold}: set clarifying_questions to [] — macros are on the label.
- All other cases: generate 3–5 targeted consumption-context questions. Cover ALL that apply:
  1. Serving size / quantity — "select" with realistic food-specific options (tortillas: ["1", "2", "3", "4 or more"]; pizza: ["1 slice", "2 slices", "Half", "Whole"]).
  2. Preparation or variant — only if it meaningfully changes macros (grilled vs fried, flour vs corn, sauce type).
  3. Current goal — ["Lose weight", "Build muscle", "Maintain weight", "Just curious"] — SKIP if dietary profile has a goal.
  4. Frequency — ["First time", "Occasionally", "Few times a week", "Almost daily"].
  5. Filling / topping if food is incomplete without it (tacos, sandwiches, bowls).

- ALWAYS prefer "select" with short, food-specific options.
- "boolean" ONLY for true yes/no.
- "number" ONLY when options genuinely don't work.
- Option labels: 1–5 words, natural, specific. No "Other" or "N/A".
- Do NOT ask about things visible in the image.
- Do NOT ask generic restriction questions — use dietary profile context instead.

{dietary_context}
"""


_ANALYZE_SYSTEM = """You are Buddy — the user's closest friend who thinks like Andrew Huberman and has the knowledge of a pro nutritionist. You talk like you're texting, not writing a report. You know the science cold but you never sound like a doctor, a label, or an AI assistant. Be honest, direct, real. Use contractions. Get to the point. If the food is bad for their goal, say so bluntly but warmly. If it's good, be genuinely hyped. Never hedge, never say "in moderation" without being specific, never write a wall of clinical text.

Scan data: {scan_data}
User answers: {user_answers}
Dietary profile: {dietary_profile}

Return ONLY valid JSON — no markdown, no prose:
{{
  "food_name": "<specific name with prep + serving — e.g. '2 flour tortillas, plain' or 'Double cheeseburger with fries'>",
  "headline": "<your immediate gut reaction, 8–14 words, sounds like a voice note from a close friend. Honest. Can be blunt, enthusiastic, or funny. No corporate speak. No AI phrases. Examples: 'okay this is actually not bad at all for muscle', 'bro that sodium is going to haunt you today', 'sneaky one — looks light but it is not', 'this is genuinely solid for where you are right now'>",
  "macros": {{
    "calories": <number>,
    "protein_g": <number>,
    "carbs_g": <number>,
    "fat_g": <number>,
    "sugar_g": <number>,
    "sodium_mg": <number>,
    "fiber_g": <number>
  }},
  "key_nutrients": [
    {{
      "name": "<Protein | Calories | Carbs | Sugar | Sodium | Fat | Fiber>",
      "value": "<amount + unit — e.g. '28g' or '820mg' or '420 kcal'>",
      "context": "<5–9 words, plain English, what this number means for THIS person's goal — e.g. 'solid muscle recovery fuel', 'half your daily sodium right there', 'barely moves the needle', 'going to spike your blood sugar'>",
      "sentiment": "good" | "neutral" | "watch"
    }}
  ],
  "recommendation": "eat" | "moderate" | "skip",
  "verdict_reason": "<2–3 sentences in Buddy's voice. Sound like a knowledgeable friend, not a label. Use contractions. Name the goal. Be specific — reference the actual macros or ingredients. No hedging, no generic advice.>",
  "pros": [
    "<max 15 words, friend voice, one specific benefit for this person's goal>",
    "<another if genuinely there>"
  ],
  "cons": [
    "<max 15 words, friend voice, one specific drawback for this person's goal>",
    "<another if genuinely there>"
  ],
  "concerns": ["<any flags not already covered above — keep short>"]
}}

key_nutrients rules:
- Only return 2–4 nutrients that actually matter for THIS food + THIS goal.
- Protein bar for muscle builder → protein first, sugar second.
- Tortillas for weight loss → carbs and calories first.
- Salad with dressing → sodium and fat if notable.
- Skip anything that is not actionable for this specific person.
- Context must sound like something you'd say out loud, not a textbook.

Recommendation logic:
- "eat": genuinely supports the goal — be enthusiastic.
- "moderate": real tradeoff exists — name it specifically, don't just say "occasionally".
- "skip": clearly fights the goal — be honest, not harsh.

Pros/Cons:
- 2–4 each. No filler. Don't repeat verdict_reason.
- Use "your" not "the user's".
- If there are no real pros, say so honestly — don't invent them.
- Macros must match the serving size from user answers.
"""


def _strip_fences(text: str) -> str:
    """Remove markdown code fences Gemini sometimes wraps JSON in."""
    text = re.sub(r"^```(?:json)?\s*", "", text, flags=re.MULTILINE)
    text = re.sub(r"\s*```$", "", text, flags=re.MULTILINE)
    return text.strip()


def _fallback_scan(scan_id: str) -> ScanResult:
    """Returned when Gemini output can't be parsed — forces the user to clarify."""
    return ScanResult(
        scan_id=scan_id,
        detected_type="unknown",
        detected_items=[],
        confidence=0.0,
        raw_text="",
        clarifying_questions=[
            ScanQuestion(
                id="q_item",
                text="The image wasn't clear enough to identify the food. What is it?",
                input_type="text",
                options=[],
            ),
            ScanQuestion(
                id="q_servings",
                text="How many servings are you having?",
                input_type="number",
                options=[],
            ),
        ],
        needs_clarification=True,
        food_category="",
    )


# Client

class GeminiClient:
    """Async wrapper around Google Gen AI SDK (Gemini Developer API)."""

    def __init__(self) -> None:
        if not settings.GEMINI_API_KEY:
            raise ValueError("GEMINI_API_KEY is not configured — nutrition scan unavailable")

        from google import genai  # type: ignore
        from google.genai import types  # type: ignore

        self._client = genai.Client(api_key=settings.GEMINI_API_KEY)
        self._types = types
        # Scan: low temp — deterministic structured extraction from an image.
        self._scan_config = types.GenerateContentConfig(
            temperature=0.1,
            top_p=0.95,
            max_output_tokens=2048,
            response_mime_type="application/json",
        )
        # Analyze: higher temp — Buddy's voice needs personality, not just structure.
        self._analyze_config = types.GenerateContentConfig(
            temperature=0.7,
            top_p=0.95,
            max_output_tokens=4096,
            response_mime_type="application/json",
        )

    def _call_sync(self, contents: list, config: Any) -> str:
        last_exc: Exception | None = None
        for attempt in range(1, _MAX_RETRIES + 1):
            try:
                response = self._client.models.generate_content(
                    model=settings.GEMINI_NUTRITION_MODEL,
                    contents=contents,
                    config=config,
                )
                return response.text or ""
            except Exception as exc:
                # google-genai raises APIError subclasses with an HTTP `.code` attribute.
                # When the SDK wraps a gRPC error, `.code` may be a gRPC StatusCode enum (e.g. UNAVAILABLE=14) rather than the integer 503, 
                # so also check the error string for known transient gRPC status names.
                code = getattr(exc, "code", None)
                error_str = str(exc).upper()
                retryable = (
                    code == 429
                    or (isinstance(code, int) and 500 <= code < 600)
                    or "UNAVAILABLE" in error_str
                    or "RESOURCE_EXHAUSTED" in error_str
                )
                if not retryable or attempt == _MAX_RETRIES:
                    logger.error("Gemini call failed", {
                        "model": settings.GEMINI_NUTRITION_MODEL,
                        "attempt": attempt,
                        "error_type": type(exc).__name__,
                        "code": code,
                        "error": str(exc),
                    })
                    raise
                last_exc = exc
                delay = _BASE_DELAY_S * (2 ** (attempt - 1)) + random.uniform(0, 0.5)
                logger.warn("Gemini retryable error, backing off", {
                    "model": settings.GEMINI_NUTRITION_MODEL,
                    "attempt": attempt,
                    "delay_s": round(delay, 2),
                    "error_type": type(exc).__name__,
                    "code": code,
                    "error": str(exc),
                })
                time.sleep(delay)
        raise last_exc  # type: ignore[misc]

    async def _call(self, contents: list, config: Any) -> str:
        return await asyncio.to_thread(self._call_sync, contents, config)

    async def scan_image(
        self,
        image_bytes: bytes,
        mime_type: str = "image/jpeg",
        dietary_profile: dict[str, Any] | None = None,
        scan_id: str | None = None,
    ) -> ScanResult:
        sid = scan_id or str(uuid.uuid4())
        dietary_context = (
            f"User dietary profile for contextual questions: {json.dumps(dietary_profile)}"
            if dietary_profile else ""
        )
        prompt = _SCAN_SYSTEM.format(
            threshold=settings.NUTRITION_SCAN_CONFIDENCE_THRESHOLD,
            dietary_context=dietary_context,
        )

        image_part = self._types.Part.from_bytes(data=image_bytes, mime_type=mime_type)

        try:
            raw = await self._call([image_part, prompt], self._scan_config)
            data = json.loads(_strip_fences(raw))

            questions = [
                ScanQuestion(
                    id=q.get("id", f"q{i}"),
                    text=str(q["text"]),
                    input_type=q.get("input_type", "text"),
                    options=list(q.get("options") or []),
                )
                for i, q in enumerate(data.get("clarifying_questions") or [])
                if q.get("text")
            ]

            confidence = float(data.get("confidence", 0.0))
            needs = bool(questions) or confidence < settings.NUTRITION_SCAN_CONFIDENCE_THRESHOLD

            logger.info("Gemini scan_image OK", {
                "scan_id": sid,
                "detected_type": data.get("detected_type"),
                "food_category": data.get("food_category"),
                "confidence": confidence,
                "questions": len(questions),
            })

            return ScanResult(
                scan_id=sid,
                detected_type=str(data.get("detected_type", "unknown")),
                detected_items=list(data.get("detected_items") or []),
                confidence=confidence,
                raw_text=str(data.get("raw_text") or ""),
                clarifying_questions=questions,
                needs_clarification=needs,
                food_category=str(data.get("food_category") or ""),
            )

        except (json.JSONDecodeError, KeyError, TypeError) as exc:
            logger.error("Gemini scan_image parse failed", {"scan_id": sid, "error": str(exc)})
            return _fallback_scan(sid)

    async def analyze_food(
        self,
        scan_result: ScanResult,
        user_answers: dict[str, Any],
        dietary_profile: dict[str, Any] | None = None,
    ) -> AnalysisResult:
        scan_data = {
            "detected_type": scan_result.detected_type,
            "detected_items": scan_result.detected_items,
            "confidence": scan_result.confidence,
            "raw_text": scan_result.raw_text,
        }
        prompt = _ANALYZE_SYSTEM.format(
            scan_data=json.dumps(scan_data),
            user_answers=json.dumps(user_answers),
            dietary_profile=json.dumps(dietary_profile or {}),
        )

        try:
            raw = await self._call([prompt], self._analyze_config)
            data = json.loads(_strip_fences(raw))
            macros_raw = data.get("macros") or {}

            result = AnalysisResult(
                food_name=str(data.get("food_name", "Unknown Food")),
                headline=str(data.get("headline", "")),
                macros={
                    "calories": float(macros_raw.get("calories", 0)),
                    "protein_g": float(macros_raw.get("protein_g", 0)),
                    "carbs_g": float(macros_raw.get("carbs_g", 0)),
                    "fat_g": float(macros_raw.get("fat_g", 0)),
                    "sugar_g": float(macros_raw.get("sugar_g", 0)),
                    "sodium_mg": float(macros_raw.get("sodium_mg", 0)),
                    "fiber_g": float(macros_raw.get("fiber_g", 0)),
                },
                key_nutrients=list(data.get("key_nutrients") or []),
                recommendation=str(data.get("recommendation", "moderate")),
                verdict_reason=str(data.get("verdict_reason", "")),
                concerns=list(data.get("concerns") or []),
                pros=list(data.get("pros") or []),
                cons=list(data.get("cons") or []),
            )

            logger.info("Gemini analyze_food OK", {
                "scan_id": scan_result.scan_id,
                "food_name": result.food_name,
                "recommendation": result.recommendation,
            })
            return result

        except (json.JSONDecodeError, KeyError, TypeError) as exc:
            logger.error("Gemini analyze_food parse failed", {
                "scan_id": scan_result.scan_id,
                "error": str(exc),
            })
            raise ValueError(f"Nutrition analysis failed: {exc}") from exc


# Module-level singleton

_client: GeminiClient | None = None


def get_gemini_client() -> GeminiClient:
    global _client
    if _client is None:
        _client = GeminiClient()
    return _client
