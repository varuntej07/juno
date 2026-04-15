"""
PushNotificationAgent — verifies a DailyPlan before it is scheduled.

Two-stage verification to avoid unnecessary LLM calls:

Stage 1 (pure Python, no LLM):
  - Both send times within allowed windows?
  - At least 4 hours between morning and evening nudge?
  - Both nudges on different topics?
  - Topics not identical to yesterday's?

Stage 2 (single ModelProvider.fast() call):
  - Tone appropriate for the user's profile?
  - Any sensitivity flags (eating disorders, mental health triggers)?
  - Content specific enough — no generic filler?

If Stage 1 fails, we skip Stage 2 entirely and return rejection immediately.
The feedback_for_planner field is always concrete and actionable so the
planner can fix the issue on its one retry attempt.
"""

from __future__ import annotations

from datetime import time

from ..model_provider import ModelProvider
from .models import DailyPlan, VerificationResult


# Allowed send windows (inclusive bounds, local time)
MORNING_WINDOW_START = time(8, 0)    # 8:00 AM
MORNING_WINDOW_END   = time(12, 0)   # 12:00 PM
EVENING_WINDOW_START = time(17, 0)   # 5:00 PM
EVENING_WINDOW_END   = time(21, 0)   # 9:00 PM

# Minimum gap required between morning and evening nudge
MIN_GAP_BETWEEN_NUDGES_HOURS = 4


_VERIFIER_SYSTEM_PROMPT = """You are a quality gate for Juno's daily push notifications.
Review the proposed DailyPlan and decide whether it is appropriate to send.

Check all of the following:
1. TONE — Is the tone suitable for the user's dietary profile and history?
   Reject if the tone is condescending, alarmist, or mismatched with the context.

2. SENSITIVITY — Does any content risk triggering eating disorder concerns,
   body-image anxiety, or mental health distress?
   Reject if any nudge body or opening_chat_message references:
     - specific calorie counts as a primary metric
     - phrases like "you ate too much", "you're failing", "disgusting choice"
     - extreme diet language ("starvation", "binge", "purge")

3. SPECIFICITY — Is the content specific enough to be worth tapping?
   Reject if either nudge sounds like a generic wellness app:
     - "Stay hydrated today!"
     - "Don't forget to take care of yourself!"
     - "Here's a health tip for you!"
   Accept if the content references something real from the user's queries,
   profile, or the provided news item.

If everything passes, return approved=true with null for rejection_reason and feedback_for_planner.

If anything fails, return approved=false with:
  - rejection_reason: one sentence explaining the problem
  - feedback_for_planner: exactly what to fix, specific enough that a language model
    can act on it without guessing (mention which nudge, which field, what to change)

Return ONLY valid JSON:
{
  "approved": true | false,
  "rejection_reason": "..." | null,
  "feedback_for_planner": "..." | null
}"""


class PushNotificationAgent:
    def __init__(self, models: ModelProvider) -> None:
        self._models = models

    async def verify(
        self,
        plan: DailyPlan,
        topics_sent_yesterday: list[str],
        dietary_profile: dict,
    ) -> VerificationResult:
        """Verify a DailyPlan before scheduling.

        Args:
            plan: The DailyPlan from NotificationPlannerAgent.
            user_timezone: IANA timezone string e.g. "Asia/Kolkata".
            topics_sent_yesterday: Topics from the last 2 daily_plans.
            dietary_profile: User's dietary profile dict.

        Returns:
            VerificationResult with approved=True or rejection with feedback.
        """
        # Stage 1: hard rules — no LLM needed
        hard_check = _check_hard_rules(plan, topics_sent_yesterday)
        if hard_check is not None:
            return hard_check

        # Stage 2: LLM tone, sensitivity, and specificity check
        return await self._llm_check(plan, dietary_profile)

    async def _llm_check(self, plan: DailyPlan, dietary_profile: dict) -> VerificationResult:
        profile_summary = _summarise_profile(dietary_profile)
        prompt = f"""Review this DailyPlan for tone, sensitivity, and specificity.

DIETARY PROFILE:
{profile_summary}

MORNING NUDGE:
  topic: {plan.morning_nudge.topic}
  title: {plan.morning_nudge.title}
  body: {plan.morning_nudge.body}
  opening_chat_message: {plan.morning_nudge.opening_chat_message}
  why_this_topic: {plan.morning_nudge.why_this_topic}

EVENING NUDGE:
  topic: {plan.evening_nudge.topic}
  title: {plan.evening_nudge.title}
  body: {plan.evening_nudge.body}
  opening_chat_message: {plan.evening_nudge.opening_chat_message}
  why_this_topic: {plan.evening_nudge.why_this_topic}

Does this plan pass all checks? Return JSON only."""

        return await self._models.fast(
            prompt,
            system=_VERIFIER_SYSTEM_PROMPT,
            response_model=VerificationResult,
        )


# ── Hard rule checks (pure Python, no LLM) ───────────────────────────────────

def _check_hard_rules(
    plan: DailyPlan,
    topics_sent_yesterday: list[str],
) -> VerificationResult | None:
    """Run all hard rules. Returns VerificationResult on first failure, None if all pass."""

    morning_time = _parse_local_time(plan.morning_nudge.send_at_local_time)
    evening_time = _parse_local_time(plan.evening_nudge.send_at_local_time)

    # Rule 1: morning nudge must be in the 8 AM–12 PM window
    if morning_time is None or not (MORNING_WINDOW_START <= morning_time <= MORNING_WINDOW_END):
        return VerificationResult(
            approved=False,
            rejection_reason=f"morning_nudge.send_at_local_time '{plan.morning_nudge.send_at_local_time}' is outside the 08:00–12:00 window",
            feedback_for_planner=(
                f"morning_nudge.send_at_local_time must be between 08:00 and 12:00. "
                f"You set it to '{plan.morning_nudge.send_at_local_time}'. Pick a time like '08:30' or '10:00'."
            ),
        )

    # Rule 2: evening nudge must be in the 5 PM–9 PM window
    if evening_time is None or not (EVENING_WINDOW_START <= evening_time <= EVENING_WINDOW_END):
        return VerificationResult(
            approved=False,
            rejection_reason=f"evening_nudge.send_at_local_time '{plan.evening_nudge.send_at_local_time}' is outside the 17:00–21:00 window",
            feedback_for_planner=(
                f"evening_nudge.send_at_local_time must be between 17:00 and 21:00. "
                f"You set it to '{plan.evening_nudge.send_at_local_time}'. Pick a time like '18:30' or '19:00'."
            ),
        )

    # Rule 3: at least MIN_GAP_BETWEEN_NUDGES_HOURS between the two send times
    morning_minutes = morning_time.hour * 60 + morning_time.minute
    evening_minutes = evening_time.hour * 60 + evening_time.minute
    gap_hours = (evening_minutes - morning_minutes) / 60
    if gap_hours < MIN_GAP_BETWEEN_NUDGES_HOURS:
        return VerificationResult(
            approved=False,
            rejection_reason=f"gap between morning ({plan.morning_nudge.send_at_local_time}) and evening ({plan.evening_nudge.send_at_local_time}) nudge is only {gap_hours:.1f}h — minimum is {MIN_GAP_BETWEEN_NUDGES_HOURS}h",
            feedback_for_planner=(
                f"The morning and evening nudges are too close together ({gap_hours:.1f}h apart). "
                f"Ensure at least {MIN_GAP_BETWEEN_NUDGES_HOURS} hours between them. "
                f"For example: morning at '09:00' and evening at '18:00'."
            ),
        )

    # Rule 4: both nudges must be on different topics
    if plan.morning_nudge.topic == plan.evening_nudge.topic:
        return VerificationResult(
            approved=False,
            rejection_reason=f"both nudges are on the same topic '{plan.morning_nudge.topic}'",
            feedback_for_planner=(
                f"morning_nudge and evening_nudge are both on topic '{plan.morning_nudge.topic}'. "
                f"Change evening_nudge to a different topic — for example 'workout', 'sleep', or 'news'."
            ),
        )

    # Rule 5: don't repeat topics from the last two days
    new_topics = {plan.morning_nudge.topic, plan.evening_nudge.topic}
    repeated = new_topics.intersection(set(topics_sent_yesterday))
    if len(repeated) == len(new_topics) and topics_sent_yesterday:
        # Both topics were used yesterday — require at least one fresh topic
        return VerificationResult(
            approved=False,
            rejection_reason=f"both topics ({', '.join(new_topics)}) were already sent in the last 2 days",
            feedback_for_planner=(
                f"Topics {', '.join(repeated)} were already sent recently. "
                f"Change at least one nudge to a fresh topic not in: {', '.join(topics_sent_yesterday)}."
            ),
        )

    # All hard rules passed
    return None


def _parse_local_time(time_str: str) -> time | None:
    """Parse "HH:MM" string to time object. Returns None on failure."""
    try:
        parts = time_str.strip().split(":")
        if len(parts) == 2:
            return time(int(parts[0]), int(parts[1]))
    except (ValueError, AttributeError):
        pass
    return None


def _summarise_profile(profile: dict) -> str:
    if not profile:
        return "No dietary profile available."
    lines = []
    for key in ("goal", "restrictions", "allergies", "activity_level", "age", "gender"):
        val = profile.get(key)
        if val:
            lines.append(f"  {key}: {val}")
    return "\n".join(lines) if lines else "No dietary profile available."
