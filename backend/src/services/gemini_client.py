"""
Gemini client via Google Gen AI SDK (google-genai).

Uses Application Default Credentials (ADC) with Vertex AI backend —
works automatically on Cloud Run with the attached service account.
No API key required.

Two public async methods:
  - scan_image()   → detect food / read nutrition label, return confidence + questions
  - analyze_food() → full macro + verdict analysis given answers + dietary profile
"""

from __future__ import annotations

import asyncio
import json
import re
import uuid
from dataclasses import dataclass, field
from typing import Any

from ..config.settings import settings
from ..lib.logger import logger


# ─── Data classes returned to callers ────────────────────────────────────────

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


@dataclass
class AnalysisResult:
    food_name: str
    macros: dict[str, float]    # calories, protein_g, carbs_g, fat_g, sugar_g, sodium_mg, fiber_g
    recommendation: str         # "eat" | "moderate" | "skip"
    verdict_reason: str
    concerns: list[str]


# ─── Prompts ─────────────────────────────────────────────────────────────────

_SCAN_SYSTEM = """You are a precision nutrition analysis AI. Analyze the image and return ONLY valid JSON — no markdown, no prose.

Detect what is shown:
- "nutrition_label": a packaged food nutrition facts panel (tabular text with calories, macros)
- "restaurant_food": a plated dish or restaurant meal
- "packaged_food": a packaged product where the label isn't fully visible
- "unknown": cannot determine

Return this exact JSON structure:
{{
  "detected_type": "<type>",
  "detected_items": ["<item1>", "<item2>"],
  "confidence": <0.0 to 1.0>,
  "raw_text": "<full extracted text from nutrition label, empty string if not a label>",
  "clarifying_questions": [
    {{
      "id": "q1",
      "text": "<question>",
      "input_type": "select" | "text" | "number" | "boolean",
      "options": ["<opt1>", "<opt2>"]
    }}
  ]
}}

Rules for clarifying_questions:
- confidence >= {threshold} AND detected_type == "nutrition_label" with clear macro values → return []
- confidence < {threshold} OR food is ambiguous → generate 2-5 targeted questions
- Good questions ask: exact food item, preparation method, portion/serving size, occasion
- For restaurant food: always ask serving size and preparation (fried/grilled/etc.)
- Always ask about servings if quantity is unclear from the label
- Do NOT ask questions you can already answer from the image

{dietary_context}"""


_ANALYZE_SYSTEM = """You are a nutrition expert. Given the food scan data, user clarifications, and their dietary profile, return a precise nutrition analysis as ONLY valid JSON — no markdown, no prose.

Scan data: {scan_data}
User answers: {user_answers}
Dietary profile: {dietary_profile}

Return this exact JSON structure:
{{
  "food_name": "<descriptive name>",
  "macros": {{
    "calories": <number>,
    "protein_g": <number>,
    "carbs_g": <number>,
    "fat_g": <number>,
    "sugar_g": <number>,
    "sodium_mg": <number>,
    "fiber_g": <number>
  }},
  "recommendation": "eat" | "moderate" | "skip",
  "verdict_reason": "<2-3 sentences tailored to this user's goal and restrictions>",
  "concerns": ["<concern1>", "<concern2>"]
}}

Recommendation logic:
- "eat": fits the user's goals, good macros, appropriate portion
- "moderate": acceptable occasionally, watch portion/frequency
- "skip": clearly conflicts with the user's goals or health restrictions

If no dietary profile provided, use general healthy-eating guidelines.
Be honest and specific. Adjust macros for the serving size the user indicated."""


# ─── Helpers ─────────────────────────────────────────────────────────────────

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
    )


# ─── Client ──────────────────────────────────────────────────────────────────

class GeminiClient:
    """Async wrapper around Google Gen AI SDK with Vertex AI backend."""

    def __init__(self) -> None:
        from google import genai  # type: ignore
        from google.genai import types  # type: ignore

        self._client = genai.Client(
            vertexai=True,
            project=settings.VERTEX_AI_PROJECT,
            location=settings.VERTEX_AI_LOCATION,
        )
        self._types = types
        self._config = types.GenerateContentConfig(
            temperature=0.1,
            top_p=0.95,
            max_output_tokens=2048,
        )

    def _call_sync(self, contents: list) -> str:
        response = self._client.models.generate_content(
            model=settings.GEMINI_MODEL,
            contents=contents,
            config=self._config,
        )
        return response.text

    async def _call(self, contents: list) -> str:
        return await asyncio.to_thread(self._call_sync, contents)

    # ── scan_image ────────────────────────────────────────────────────────────

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
            raw = await self._call([image_part, prompt])
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
            )

        except (json.JSONDecodeError, KeyError, TypeError) as exc:
            logger.error("Gemini scan_image parse failed", {"scan_id": sid, "error": str(exc)})
            return _fallback_scan(sid)

    # ── analyze_food ──────────────────────────────────────────────────────────

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
            raw = await self._call([prompt])
            data = json.loads(_strip_fences(raw))
            macros_raw = data.get("macros") or {}

            result = AnalysisResult(
                food_name=str(data.get("food_name", "Unknown Food")),
                macros={
                    "calories":   float(macros_raw.get("calories",   0)),
                    "protein_g":  float(macros_raw.get("protein_g",  0)),
                    "carbs_g":    float(macros_raw.get("carbs_g",    0)),
                    "fat_g":      float(macros_raw.get("fat_g",      0)),
                    "sugar_g":    float(macros_raw.get("sugar_g",    0)),
                    "sodium_mg":  float(macros_raw.get("sodium_mg",  0)),
                    "fiber_g":    float(macros_raw.get("fiber_g",    0)),
                },
                recommendation=str(data.get("recommendation", "moderate")),
                verdict_reason=str(data.get("verdict_reason", "")),
                concerns=list(data.get("concerns") or []),
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


# ─── Module-level singleton ───────────────────────────────────────────────────

_client: GeminiClient | None = None


def get_gemini_client() -> GeminiClient:
    global _client
    if _client is None:
        _client = GeminiClient()
    return _client
