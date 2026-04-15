"""
Pydantic models for the daily notification planning pipeline.

DailyPlan is the output of NotificationPlannerAgent and the input to PushNotificationAgent.
VerificationResult is the output of PushNotificationAgent.
"""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict


class NudgePlan(BaseModel):
    model_config = ConfigDict(strict=True)

    topic: str
    """One of: "nutrition" | "workout" | "sleep" | "news" | "habit" | "hydration" | "mindfulness" """

    title: str
    """Notification title shown on lock screen. Max 50 characters."""

    body: str
    """Notification body shown on lock screen. Max 100 characters."""

    send_at_local_time: str
    """Time to deliver in the user's timezone. Format: "HH:MM" e.g. "08:30" """

    send_at_utc: str
    """ISO 8601 UTC datetime for scheduling the Cloud Task. e.g. "2026-04-14T03:00:00+00:00" """

    why_this_topic: str
    """Internal rationale for this nudge — not shown to the user.
    Explains which query signals or news items drove this choice."""

    opening_chat_message: str
    """The first message Juno sends when the user taps the notification and opens chat.
    Should feel like continuing a conversation, not starting from zero.
    1–2 sentences."""

    quick_reply_chips: list[str]
    """2–3 short tap-to-reply options shown under the notification.
    Examples: ["Tell me more", "I already did!", "Skip for now"]"""


class DailyPlan(BaseModel):
    model_config = ConfigDict(strict=True)

    morning_nudge: NudgePlan
    """Scheduled between 8 AM and 12 PM in the user's local timezone."""

    evening_nudge: NudgePlan
    """Scheduled between 5 PM and 9 PM in the user's local timezone."""

    plan_source: Literal["query_based", "news_fallback", "safe_default"]
    """
    query_based  — planner found clear patterns in the user's recent query history
    news_fallback — query signal was thin; content is framed around relevant news
    safe_default — both planner attempts failed; generic but always valid fallback
    """


class VerificationResult(BaseModel):
    model_config = ConfigDict(strict=True)

    approved: bool
    """True if the plan passes all checks and is ready to schedule."""

    rejection_reason: str | None
    """Human-readable description of why the plan was rejected.
    None when approved=True."""

    feedback_for_planner: str | None
    """Actionable feedback injected verbatim into the planner's retry prompt.
    Must be specific enough for the planner to act on without guessing.
    Examples:
      "morning_nudge.send_at_local_time is 03:00 — must be between 08:00 and 12:00"
      "both nudges are on topic 'nutrition' — make evening_nudge a different topic"
      "evening_nudge.body is generic; reference a specific item from the user's query history"
    None when approved=True."""
