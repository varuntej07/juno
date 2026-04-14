"""
DecisionEngine — pure Python, zero LLM calls.

Decides whether to engage the user, which agent to use, and what tone to strike.
All rules are hard constraints encoded as logic — not heuristics fed to Claude.

Tone selection for nutrition_followup:
    past_scan_count == 0                 → "educate"  (first time, explain)
    1 <= past_scan_count < 3, bad verdict → "warn"    (seen before, heads up)
    past_scan_count >= 3, bad verdict    → "roast"    (they keep doing it)
    verdict == "eat"                     → "celebrate" (good choice)
    no recent bad scan                   → "check_in"

Rate-limit rules (all checked atomically via Firestore transaction in orchestrator.py):
    min 2h between any notifications
    max 3 proactive notifications per day
    quiet hours: 10pm–8am (UTC; expand when we have user timezone)
    suppress if last query was < 5min ago (user is active in app)
"""

from __future__ import annotations

import random
from datetime import datetime, timezone
from typing import Any

from .models import EngagementDecision


# ── Config ────────────────────────────────────────────────────────────────────

_MIN_GAP_HOURS = 2
_MAX_PROACTIVE_PER_DAY = 3
_QUIET_HOUR_START = 22   # 10pm UTC
_QUIET_HOUR_END = 8      # 8am UTC
_ACTIVE_SESSION_WINDOW_MINUTES = 5


# ── Public entry point ────────────────────────────────────────────────────────

def decide(
    trigger_event: str,
    trigger_payload: dict[str, Any],
    context: dict[str, Any],
) -> EngagementDecision:
    """
    Pure function. No I/O. Takes assembled context, returns EngagementDecision.

    Args:
        trigger_event:   "nutrition_scan" | "chat_query" | "calendar_event"
        trigger_payload: raw event data (nutrition log doc, query text, etc.)
        context: {
            recent_nutrition_logs: list[dict],
            dietary_profile: dict | None,
            engagement_guard: dict | None,   # {last_engaged_at, count_today, guard_date, last_app_interaction_at}
            upcoming_events: list[dict],
            memories: list[dict],
        }
    """
    now = datetime.now(timezone.utc)
    guard = context.get("engagement_guard") or {}

    # ── Hard gate: rate-limit checks ─────────────────────────────────────────
    suppression = _check_suppression(now, guard)
    if suppression:
        return EngagementDecision(
            should_engage=False,
            chosen_agent="none",
            delay_minutes=0,
            tone="check_in",
            engagement_context={},
            suppression_reason=suppression,
        )

    # ── Route by trigger event ────────────────────────────────────────────────
    if trigger_event == "nutrition_scan":
        return _decide_nutrition(trigger_payload, context)

    if trigger_event == "calendar_event":
        return _decide_calendar(trigger_payload, context)

    if trigger_event == "chat_query":
        return _decide_habit(trigger_payload, context)

    return EngagementDecision(
        should_engage=False,
        chosen_agent="none",
        delay_minutes=0,
        tone="check_in",
        engagement_context={},
        suppression_reason=f"unrecognised_trigger:{trigger_event}",
    )


# ── Suppression checks ────────────────────────────────────────────────────────

def _check_suppression(now: datetime, guard: dict[str, Any]) -> str | None:
    """Return a suppression_reason string if we should NOT engage, else None."""

    # Quiet hours (UTC)
    if _QUIET_HOUR_START <= now.hour or now.hour < _QUIET_HOUR_END:
        return "quiet_hours"

    # User is actively using the app right now
    last_interaction = guard.get("last_app_interaction_at")
    if last_interaction:
        try:
            last_dt = datetime.fromisoformat(last_interaction)
            minutes_ago = (now - last_dt).total_seconds() / 60
            if minutes_ago < _ACTIVE_SESSION_WINDOW_MINUTES:
                return "user_active_in_app"
        except ValueError:
            pass

    # Time gap since last notification
    last_engaged = guard.get("last_engaged_at")
    if last_engaged:
        try:
            last_dt = datetime.fromisoformat(last_engaged)
            hours_ago = (now - last_dt).total_seconds() / 3600
            if hours_ago < _MIN_GAP_HOURS:
                return "too_recent"
        except ValueError:
            pass

    # Daily cap — only proactive (cold) notifications count against the cap;
    # interaction-triggered ones (nutrition scan, calendar) are exempt.
    today = now.date().isoformat()
    if guard.get("guard_date") == today:
        proactive_count = guard.get("proactive_count_today", 0)
        if proactive_count >= _MAX_PROACTIVE_PER_DAY:
            return "daily_cap"

    return None


# ── Trigger-specific decision logic ──────────────────────────────────────────

def _decide_nutrition(
    payload: dict[str, Any],
    context: dict[str, Any],
) -> EngagementDecision:
    food_name: str = payload.get("food_name", "").strip().lower()
    verdict: str = payload.get("recommendation", "moderate")   # "eat"|"moderate"|"skip"
    concerns: list[str] = payload.get("concerns", [])

    # Count past scans of the same food (case-insensitive)
    logs: list[dict] = context.get("recent_nutrition_logs", [])
    past_scans = sum(
        1 for log in logs
        if log.get("food_name", "").strip().lower() == food_name
    )

    # Tone selection — fully deterministic
    if verdict == "eat":
        tone = "celebrate"
    elif past_scans == 0:
        tone = "educate"
    elif past_scans < 3:
        tone = "warn"
    else:
        tone = "roast"

    # Only engage if there's something worth saying
    if verdict == "eat" and not concerns:
        # Good food, no concerns — only engage sometimes to avoid noise
        # Simple deterministic rule: engage if this is a notably healthy choice
        # (high protein, low concerns). For now always engage on good verdict.
        pass
    elif verdict == "moderate" and past_scans == 0 and not concerns:
        # First scan, meh food, nothing specific to say — skip
        return EngagementDecision(
            should_engage=False,
            chosen_agent="none",
            delay_minutes=0,
            tone=tone,
            engagement_context={},
            suppression_reason="nothing_notable",
        )

    engagement_context: dict[str, Any] = {
        "food_name": payload.get("food_name", "Unknown"),
        "first_time": past_scans == 0,
        "past_scan_count": past_scans,
        "concerns": concerns,
        "verdict": verdict,
        "verdict_reason": payload.get("verdict_reason", ""),
        "macros": payload.get("macros", {}),
    }

    # Add dietary background if available
    profile = context.get("dietary_profile") or {}
    if profile:
        engagement_context["dietary_goal"] = profile.get("goal", "")
        engagement_context["restrictions"] = profile.get("restrictions", [])
        engagement_context["allergies"] = profile.get("allergies", [])

    return EngagementDecision(
        should_engage=True,
        chosen_agent="nutrition_followup",
        delay_minutes=_random_delay(30, 60),
        tone=tone,
        engagement_context=engagement_context,
    )


def _decide_calendar(
    payload: dict[str, Any],
    context: dict[str, Any],   # reserved: dietary profile / memories used in future
) -> EngagementDecision:
    _ = context
    event_title: str = payload.get("title", "Meeting")
    minutes_until: int = payload.get("minutes_until", 180)
    description: str = payload.get("description", "")

    # Only prep notifications for events within 3 hours
    if minutes_until > 180:
        return EngagementDecision(
            should_engage=False,
            chosen_agent="none",
            delay_minutes=0,
            tone="check_in",
            engagement_context={},
            suppression_reason="event_too_far",
        )

    return EngagementDecision(
        should_engage=True,
        chosen_agent="calendar_prep",
        delay_minutes=2,   # near-immediate for time-sensitive prep
        tone="check_in",
        engagement_context={
            "event_title": event_title,
            "minutes_until": minutes_until,
            "description": description,
            "attendees": payload.get("attendees", []),
        },
    )


def _decide_habit(
    _payload: dict[str, Any],   # reserved: original query text used in future
    context: dict[str, Any],
) -> EngagementDecision:
    """Detect habit signals from query history. Called when trigger_event == 'chat_query'."""
    signals = _detect_habit_signals(context)

    if not signals:
        return EngagementDecision(
            should_engage=False,
            chosen_agent="none",
            delay_minutes=0,
            tone="check_in",
            engagement_context={},
            suppression_reason="no_habit_signal",
        )

    # Pick the strongest signal
    chosen_signal = max(signals.items(), key=lambda kv: kv[1].get("strength", 0))
    signal_key, signal_data = chosen_signal

    return EngagementDecision(
        should_engage=True,
        chosen_agent="habit_nudge",
        delay_minutes=_random_delay(45, 90),
        tone="check_in",
        engagement_context={
            "signal": signal_key,
            **signal_data,
        },
    )


def _detect_habit_signals(context: dict[str, Any]) -> dict[str, dict[str, Any]]:
    """Pure logic — scan query history for nudge-worthy patterns."""
    queries: list[dict] = context.get("recent_queries", [])
    now = datetime.now(timezone.utc)
    signals: dict[str, dict[str, Any]] = {}

    # Pattern: workout intent but no nutrition logging / scan in 5+ days
    workout_keywords = {"workout", "gym", "exercise", "run", "lift", "training"}
    workout_queries = [
        q for q in queries
        if any(kw in q.get("text", "").lower() for kw in workout_keywords)
    ]
    if workout_queries:
        latest = max(workout_queries, key=lambda q: q.get("timestamp", ""))
        try:
            days_since = (now - datetime.fromisoformat(latest["timestamp"])).days
            if days_since >= 5:
                signals["workout_intent_inactive"] = {
                    "days_since": days_since,
                    "query_count": len(workout_queries),
                    "strength": min(days_since, 10),
                }
        except (ValueError, KeyError):
            pass

    # Pattern: sleep-related query during late hours (11pm–2am)
    sleep_keywords = {"sleep", "insomnia", "tired", "rest", "bedtime"}
    late_sleep_queries = [
        q for q in queries
        if any(kw in q.get("text", "").lower() for kw in sleep_keywords)
        and _is_late_night(q.get("timestamp", ""))
    ]
    if len(late_sleep_queries) >= 2:
        signals["late_night_sleep_concern"] = {
            "occurrences": len(late_sleep_queries),
            "strength": len(late_sleep_queries) * 2,
        }

    return signals


def _is_late_night(timestamp_iso: str) -> bool:
    try:
        dt = datetime.fromisoformat(timestamp_iso)
        return dt.hour >= 23 or dt.hour < 3
    except ValueError:
        return False


def _random_delay(min_minutes: int, max_minutes: int) -> int:
    return random.randint(min_minutes, max_minutes)
