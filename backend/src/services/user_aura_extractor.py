"""
UserAuraExtractor — passive behavioral profile builder.

Fires as a fire-and-forget asyncio task after every chat message. Reads the user's
previous query from UserAura/{uid}, extracts behavioral and interest signals from the
current message via Gemini Flash, and merges the result into the UserAura document.

Never blocks the chat response stream. All failures are logged and swallowed.

Firestore path: UserAura/{uid}
"""

from __future__ import annotations

import asyncio
from datetime import datetime, timezone
from typing import Any, cast

from pydantic import BaseModel, ValidationError

from ..lib.logger import logger
from .model_provider import get_model_provider

_MAX_INFERRED_GOALS = 10

# Low temperature: we want consistent structured JSON, not creative output.
_EXTRACTION_TEMPERATURE = 0.1


class MessageInsight(BaseModel):
    # Request classification
    primary_intent: str            # task_request | seeking_advice | information_lookup |
                                   # casual_chat | venting | complaint | gratitude | follow_up_only
    secondary_intent: str | None

    # Two-layer topic extraction
    surface_topics: list[str]      # literal subjects in the message — max 3
    deep_interests: list[str]      # inferred passion/knowledge areas — max 3

    # Domain and behavioral signals
    domain: str                    # work | health | finance | learning | social |
                                   # entertainment | personal | technical | unclear
    tone: str                      # casual | terse | verbose | formal | playful
    emotional_state: str | None    # neutral | anxious | frustrated | excited | anticipatory |
                                   # curious | sad — null if not clearly signaled
    urgency: str                   # none | low | medium | high

    # Interaction preference signals
    response_depth_preference: str | None   # wants_brief | wants_detailed | wants_step_by_step |
                                            # wants_examples | wants_opinion — null if not signaled
    question_type: str | None      # how_to | what_is | opinion_request | recommendation |
                                   # comparison | troubleshooting — null if not applicable

    # Identity signals
    explicit_facts: list[str]      # only clearly stated user facts — e.g. "I live in Hyderabad"
    named_entities: list[str]      # people, places, apps, orgs mentioned — max 5
    inferred_goal_hints: list[str] # high-confidence goal inferences only — max 3

    # Metadata
    used_prev_query_context: bool  # True if the LLM used prev_query to resolve ambiguity
    extraction_skipped: bool       # True only for zero-signal messages (pure acks)


_EXTRACTION_SYSTEM_PROMPT = """\
            You are an insight extractor for a personal AI assistant called Aura.
            Analyze the user's message and extract behavioral signals, interests, and preferences.

            Rules:
            - Extract only signals you are highly confident about.
            - Use null for optional string fields and empty lists where there is no clear signal.
            - If you cannot confidently extract meaningful preferences from the current message alone,
            use the provided previous query as additional context. Set used_prev_query_context to true.
            - Always prefer the current message. Use the previous query only to resolve ambiguity or fill gaps.
            - Set extraction_skipped to true ONLY for pure acknowledgments with zero informational content
            such as standalone "ok", "thanks", "yes", "no", "sure", "got it" with nothing else attached.

            Examples of the inference depth expected:

            "Give me a tweet for the RCB vs MI match"
            surface_topics: ["RCB vs MI", "tweet writing"]
            deep_interests: ["IPL cricket", "social media content creation"]
            primary_intent: task_request, domain: entertainment, tone: casual

            "Is Triton and CUDA the same but in different languages?"
            surface_topics: ["Triton", "CUDA"]
            deep_interests: ["GPU kernel programming", "ML inference optimization"]
            question_type: comparison, domain: technical

            "Check my Gmail for any job interview updates"
            surface_topics: ["Gmail", "job interviews"]
            deep_interests: ["job hunting", "career transitions"]
            emotional_state: anticipatory
            inferred_goal_hints: ["actively expecting interview callbacks"]

            "explain SGEMM"
            surface_topics: ["SGEMM"]
            deep_interests: ["CUDA kernels", "linear algebra optimization", "GPU programming"]
            domain: technical, question_type: what_is

            Return ONLY valid JSON. No explanation, no markdown fences.
            """


def _build_extraction_prompt(message: str, prev_user_query: str | None) -> str:
    prev_block = (
        f"Previous query (use only if current message is ambiguous): {prev_user_query}\n\n"
        if prev_user_query
        else ""
    )
    return (
        f"{prev_block}"
        f"Current message: {message}\n\n"
        "Extract insights as JSON:\n"
        "{\n"
        '  "primary_intent": "task_request|seeking_advice|information_lookup|casual_chat|venting|complaint|gratitude|follow_up_only",\n'
        '  "secondary_intent": "string or null",\n'
        '  "surface_topics": ["literal subjects — max 3"],\n'
        '  "deep_interests": ["inferred passion/knowledge areas — max 3"],\n'
        '  "domain": "work|health|finance|learning|social|entertainment|personal|technical|unclear",\n'
        '  "tone": "casual|terse|verbose|formal|playful",\n'
        '  "emotional_state": "neutral|anxious|frustrated|excited|anticipatory|curious|sad or null",\n'
        '  "urgency": "none|low|medium|high",\n'
        '  "response_depth_preference": "wants_brief|wants_detailed|wants_step_by_step|wants_examples|wants_opinion or null",\n'
        '  "question_type": "how_to|what_is|opinion_request|recommendation|comparison|troubleshooting or null",\n'
        '  "explicit_facts": ["only clearly stated user facts"],\n'
        '  "named_entities": ["people, places, apps, orgs — max 5"],\n'
        '  "inferred_goal_hints": ["high-confidence goals — max 3"],\n'
        '  "used_prev_query_context": true or false,\n'
        '  "extraction_skipped": true or false\n'
        "}"
    )


def _sanitize_firestore_key(key: str) -> str:
    """
    Firestore field names cannot contain '.' or '/'.
    Keys are trimmed to 100 chars to stay well within Firestore limits.
    """
    return key.replace(".", "_").replace("/", "_").strip()[:100]


def _argmax(freq_map: dict[str, int]) -> str | None:
    return max(freq_map, key=lambda k: freq_map[k]) if freq_map else None


def _merge_profile(
    existing: dict[str, Any],
    insight: MessageInsight,
    current_message: str,
) -> dict[str, Any]:
    """
    Produce the updated UserAura document from the existing profile and a new insight.
    Pure function — no I/O. The caller writes the result to Firestore.
    """
    profile: dict[str, Any] = dict(existing)

    # Always advance the previous query pointer and timestamp regardless of skip.
    profile["prev_user_query"] = current_message
    profile["last_updated"] = datetime.now(timezone.utc).isoformat()

    if insight.extraction_skipped:
        return profile

    def _inc(map_key: str, field: str) -> None:
        freq_map: dict[str, int] = profile.setdefault(map_key, {})
        safe = _sanitize_firestore_key(field)
        freq_map[safe] = freq_map.get(safe, 0) + 1

    # Intents
    _inc("intent_distribution", insight.primary_intent)
    if insight.secondary_intent:
        _inc("intent_distribution", insight.secondary_intent)

    # Topics and interests
    for topic in insight.surface_topics:
        _inc("surface_topic_frequencies", topic)
    for interest in insight.deep_interests:
        _inc("deep_interest_frequencies", interest)

    # Domain, tone, urgency
    _inc("domain_frequencies", insight.domain)
    _inc("tone_signals", insight.tone)
    if insight.urgency != "none":
        _inc("urgency_distribution", insight.urgency)

    # Optional signals
    if insight.emotional_state:
        _inc("emotional_signals", insight.emotional_state)
    if insight.question_type:
        _inc("question_type_distribution", insight.question_type)
    if insight.response_depth_preference:
        _inc("depth_preference_signals", insight.response_depth_preference)

    # Named entities
    for entity in insight.named_entities:
        _inc("named_entities_seen", entity)

    # Lists — append with dedup (order-preserving, oldest entries kept)
    facts: list[str] = profile.setdefault("explicit_facts", [])
    for fact in insight.explicit_facts:
        if fact not in facts:
            facts.append(fact)

    goals: list[str] = profile.setdefault("inferred_goals", [])
    for goal in insight.inferred_goal_hints:
        if goal not in goals:
            goals.append(goal)
    # Keep the most recent goals when over cap — older ones are likely stale.
    if len(goals) > _MAX_INFERRED_GOALS:
        profile["inferred_goals"] = goals[-_MAX_INFERRED_GOALS:]

    # Computed dominant values — recalculated after every merge so they stay current.
    profile["dominant_tone"] = _argmax(profile.get("tone_signals", {}))
    profile["response_depth_preference"] = _argmax(profile.get("depth_preference_signals", {}))
    profile["extraction_count"] = profile.get("extraction_count", 0) + 1

    return profile


async def _read_user_aura_profile(uid: str) -> dict[str, Any]:
    from .firebase import admin_firestore

    def _fetch() -> dict[str, Any]:
        snap = admin_firestore().collection("UserAura").document(uid).get()
        return snap.to_dict() or {}

    return await asyncio.to_thread(_fetch)


async def _write_user_aura_profile(uid: str, profile: dict[str, Any]) -> None:
    from .firebase import admin_firestore

    def _put() -> None:
        admin_firestore().collection("UserAura").document(uid).set(profile)

    await asyncio.to_thread(_put)


async def extract_and_update_user_aura(uid: str, message: str) -> None:
    """
    Public entry point. Called via asyncio.create_task from the chat handler.

    Flow:
      1. Read UserAura/{uid} — retrieves prev_user_query and current profile.
      2. Build extraction prompt with current message + prev_user_query (if present).
      3. Gemini Flash extracts a MessageInsight (structured JSON).
      4. Merge insight into the profile and write back.

    All exceptions are caught and logged. This function never raises.
    """
    try:
        profile = await _read_user_aura_profile(uid)
        prev_query: str | None = profile.get("prev_user_query")

        prompt = _build_extraction_prompt(message, prev_query)
        insight = cast(MessageInsight, await get_model_provider().cheap(
            prompt,
            system=_EXTRACTION_SYSTEM_PROMPT,
            response_model=MessageInsight,
            temperature=_EXTRACTION_TEMPERATURE,
        ))

        updated = _merge_profile(profile, insight, message)
        await _write_user_aura_profile(uid, updated)

        logger.info("UserAuraExtractor: profile updated", {
            "user_id": uid,
            "primary_intent": insight.primary_intent,
            "deep_interests": insight.deep_interests,
            "domain": insight.domain,
            "extraction_skipped": insight.extraction_skipped,
            "used_prev_query": insight.used_prev_query_context,
            "extraction_count": updated.get("extraction_count"),
        })

    except ValidationError as exc:
        logger.warn("UserAuraExtractor: insight parse failed — Gemini returned malformed JSON", {
            "user_id": uid,
            "error": str(exc),
        })
    except Exception as exc:
        logger.warn("UserAuraExtractor: extraction failed", {
            "user_id": uid,
            "error": str(exc),
            "error_type": type(exc).__name__,
        })
