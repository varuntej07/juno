"""
Daily notification orchestrator — the full planning pipeline per user.

Called once per user per day, triggered by Cloud Tasks at 7 AM local time
(the fan-out handler in daily_notification.py schedules these).

Pipeline:
  1. Idempotency check — skip if daily_plans/{today} already exists
  2. Load user timezone + check daily cap
  3. Fetch context in parallel (queries, dietary profile, recent plans)
  4. Fetch RSS news headlines
  5. NotificationPlannerAgent generates DailyPlan
  6. PushNotificationAgent verifies the plan (Stage 1: hard rules, Stage 2: LLM)
  7. If rejected → retry planner ONCE with feedback injected
  8. If still rejected → use safe_default plan (never skips a day)
  9. Write daily_plans/{today} to Firestore
 10. Schedule two Cloud Tasks for morning_nudge and evening_nudge send times
"""

from __future__ import annotations

import asyncio
import json
from datetime import date, datetime, timezone, timedelta
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from ...lib.logger import logger
from ...services.firebase import admin_firestore
from ...services.model_provider import ModelProvider
from . import rss_client
from .models import DailyPlan, NudgePlan
from .planner_agent import NotificationPlannerAgent
from .verifier_agent import PushNotificationAgent


# Module-level agent singletons 
_models: ModelProvider | None = None
_planner: NotificationPlannerAgent | None = None
_verifier: PushNotificationAgent | None = None


def _get_agents() -> tuple[NotificationPlannerAgent, PushNotificationAgent]:
    global _models, _planner, _verifier
    if _models is None:
        _models = ModelProvider()
        _planner = NotificationPlannerAgent(_models)
        _verifier = PushNotificationAgent(_models)
    return _planner, _verifier  # type: ignore[return-value]


# Public entry point 
async def run_daily_plan(user_id: str) -> None:
    """Plan today's two notifications for a user. Never raises — errors are logged."""
    try:
        await _run(user_id)
    except Exception as exc:
        logger.exception("daily_notification.orchestrator: unhandled error", {
            "user_id": user_id,
            "error": str(exc),
        })


# Core pipeline 
async def _run(user_id: str) -> None:
    today = date.today().isoformat()

    # Step 1: Idempotency — skip if plan already exists for today
    if await _daily_plan_exists(user_id, today):
        logger.info("daily_notification: plan already exists, skipping", {
            "user_id": user_id,
            "date": today,
        })
        return

    # Step 2: Load timezone and check daily cap
    user_timezone = await _load_user_timezone(user_id)
    if await _daily_cap_reached(user_id, today):
        logger.info("daily_notification: daily cap already reached, skipping", {
            "user_id": user_id,
            "date": today,
        })
        return

    # Step 3: Fetch context in parallel
    queries, dietary_profile, recent_plans = await asyncio.gather(
        _fetch_last_10_queries(user_id),
        _fetch_dietary_profile(user_id),
        _fetch_last_2_daily_plans(user_id),
    )

    topics_sent_yesterday = _extract_topics_from_plans(recent_plans)
    topic_keywords = _extract_topic_keywords(queries)

    # Step 4: Fetch RSS news (used as fallback or enrichment context for the planner)
    news_items = await rss_client.fetch_news(topic_keywords)

    context: dict[str, Any] = {
        "recent_queries": queries,
        "dietary_profile": dietary_profile,
        "topics_sent_yesterday": topics_sent_yesterday,
        "news_items": news_items,
        "user_timezone": user_timezone,
        "current_local_datetime": _local_now_iso(user_timezone),
        "retry_feedback": None,
    }

    planner, verifier = _get_agents()

    # Step 5: Plan
    plan = await planner.generate(context)

    # Step 6: Verify
    result = await verifier.verify(plan, topics_sent_yesterday, dietary_profile)

    retry_count = 0
    rejection_feedback: str | None = None

    # Step 7: One retry if rejected
    if not result.approved:
        rejection_feedback = result.feedback_for_planner
        logger.info("daily_notification: plan rejected, retrying once", {
            "user_id": user_id,
            "rejection_reason": result.rejection_reason,
            "feedback": result.feedback_for_planner,
        })
        context["retry_feedback"] = result.feedback_for_planner
        retry_count = 1
        plan = await planner.generate(context)
        result = await verifier.verify(plan, topics_sent_yesterday, dietary_profile)

    # Step 8: Safe default if still rejected
    if not result.approved:
        logger.warn("daily_notification: retry also rejected, using safe default", {
            "user_id": user_id,
            "rejection_reason": result.rejection_reason,
        })
        plan = _make_safe_default_plan(news_items, user_timezone)

    # Step 9: Write daily_plans/{today}
    await _write_daily_plan(user_id, today, plan, retry_count, rejection_feedback)

    # Step 10: Schedule two Cloud Tasks
    await asyncio.gather(
        _schedule_nudge_send(user_id, today, "morning_nudge", plan.morning_nudge.send_at_utc),
        _schedule_nudge_send(user_id, today, "evening_nudge", plan.evening_nudge.send_at_utc),
    )

    logger.info("daily_notification: plan scheduled", {
        "user_id": user_id,
        "date": today,
        "plan_source": plan.plan_source,
        "morning_topic": plan.morning_nudge.topic,
        "evening_topic": plan.evening_nudge.topic,
        "retry_count": retry_count,
    })


# Safe default plan 
def _make_safe_default_plan(news_items: list[dict], user_timezone: str) -> DailyPlan:
    """Always-valid fallback. Uses the top news headline if available."""
    top_news_title = news_items[0]["title"] if news_items else "New research on health and habits"
    # Truncate to fit notification title limit
    news_title_short = (top_news_title[:47] + "...") if len(top_news_title) > 50 else top_news_title

    morning_utc = _local_hhmm_to_utc("08:30", user_timezone)
    evening_utc = _local_hhmm_to_utc("19:00", user_timezone)

    return DailyPlan(
        morning_nudge=NudgePlan(
            topic="news",
            title=news_title_short,
            body="Something worth knowing today — tap to read more.",
            send_at_local_time="08:30",
            send_at_utc=morning_utc,
            why_this_topic="Safe default: top health news headline",
            opening_chat_message=f"I came across something interesting: {top_news_title}. Thought it might be relevant to your goals.",
            quick_reply_chips=["Tell me more", "Not interested", "What else is new?"],
        ),
        evening_nudge=NudgePlan(
            topic="habit",
            title="How'd today go?",
            body="Quick check-in — let's see how the day treated you.",
            send_at_local_time="19:00",
            send_at_utc=evening_utc,
            why_this_topic="Safe default: evening wellness check-in",
            opening_chat_message="Just checking in — how did today go? Anything you want to talk through or track?",
            quick_reply_chips=["It went well!", "Could've been better", "Skip for now"],
        ),
        plan_source="safe_default",
    )


# Firestore helpers 
async def _daily_plan_exists(user_id: str, plan_date: str) -> bool:
    def _check() -> bool:
        db = admin_firestore()
        doc = (
            db.collection("users").document(user_id)
            .collection("daily_plans").document(plan_date)
            .get()
        )
        return doc.exists
    try:
        return await asyncio.to_thread(_check)
    except Exception:
        return False


async def _daily_cap_reached(user_id: str, today: str) -> bool:
    """Returns True if the user has already received their daily notification quota."""
    from ...services.engagement.decision_engine import MAX_DAILY_PROACTIVE_NOTIFICATIONS
    def _check() -> bool:
        db = admin_firestore()
        doc = (
            db.collection("users").document(user_id)
            .collection("engagement_guard").document("state")
            .get()
        )
        if not doc.exists:
            return False
        guard = doc.to_dict() or {}
        if guard.get("guard_date") != today:
            return False
        sent_today = guard.get("proactive_notifications_sent_today", 0)
        return sent_today >= MAX_DAILY_PROACTIVE_NOTIFICATIONS
    try:
        return await asyncio.to_thread(_check)
    except Exception:
        return False


async def _load_user_timezone(user_id: str) -> str:
    def _fetch() -> str:
        db = admin_firestore()
        doc = db.collection("users").document(user_id).get()
        if doc.exists:
            return (doc.to_dict() or {}).get("timezone", "UTC")
        return "UTC"
    try:
        return await asyncio.to_thread(_fetch)
    except Exception:
        return "UTC"


async def _fetch_last_10_queries(user_id: str) -> list[dict]:
    def _fetch() -> list[dict]:
        db = admin_firestore()
        docs = (
            db.collection("users").document(user_id)
            .collection("queries")
            .order_by("timestamp", direction="DESCENDING")
            .limit(10)
            .stream()
        )
        return [{"id": d.id, **d.to_dict()} for d in docs]
    try:
        return await asyncio.to_thread(_fetch)
    except Exception as exc:
        logger.warn("daily_notification: queries fetch failed", {"error": str(exc)})
        return []


async def _fetch_dietary_profile(user_id: str) -> dict:
    def _fetch() -> dict:
        db = admin_firestore()
        doc = (
            db.collection("users").document(user_id)
            .collection("dietary_profile").document("data")
            .get()
        )
        return doc.to_dict() if doc.exists else {}
    try:
        return await asyncio.to_thread(_fetch)
    except Exception as exc:
        logger.warn("daily_notification: dietary_profile fetch failed", {"error": str(exc)})
        return {}


async def _fetch_last_2_daily_plans(user_id: str) -> list[dict]:
    def _fetch() -> list[dict]:
        db = admin_firestore()
        docs = (
            db.collection("users").document(user_id)
            .collection("daily_plans")
            .order_by("plan_date", direction="DESCENDING")
            .limit(2)
            .stream()
        )
        return [d.to_dict() for d in docs]
    try:
        return await asyncio.to_thread(_fetch)
    except Exception as exc:
        logger.warn("daily_notification: daily_plans fetch failed", {"error": str(exc)})
        return []


async def _write_daily_plan(
    user_id: str,
    plan_date: str,
    plan: DailyPlan,
    retry_count: int,
    rejection_feedback: str | None,
) -> None:
    def _write() -> None:
        db = admin_firestore()
        doc: dict[str, Any] = {
            "plan_date": plan_date,
            "plan_source": plan.plan_source,
            "morning_nudge": {
                **plan.morning_nudge.model_dump(),
                "status": "scheduled",
                "cloud_task_name": None,
                "sent_at": None,
            },
            "evening_nudge": {
                **plan.evening_nudge.model_dump(),
                "status": "scheduled",
                "cloud_task_name": None,
                "sent_at": None,
            },
            "rejection_feedback": rejection_feedback,
            "retry_count": retry_count,
            "created_at": datetime.now(timezone.utc).isoformat(),
        }
        db.collection("users").document(user_id)\
            .collection("daily_plans").document(plan_date).set(doc)
    try:
        await asyncio.to_thread(_write)
    except Exception as exc:
        logger.exception("daily_notification: failed to write daily_plan", {
            "user_id": user_id,
            "error": str(exc),
        })
        raise


async def _schedule_nudge_send(
    user_id: str,
    plan_date: str,
    nudge_slot: str,
    send_at_utc: str,
) -> None:
    """Schedule a Cloud Task to fire at send_at_utc → POST /internal/daily-notify/send."""
    from ...config.settings import settings

    def _enqueue() -> str:
        from google.cloud import tasks_v2  # type: ignore
        from google.protobuf import timestamp_pb2  # type: ignore

        client = tasks_v2.CloudTasksClient()
        queue_path = client.queue_path(
            settings.CLOUD_TASKS_PROJECT,
            settings.CLOUD_TASKS_LOCATION,
            settings.CLOUD_TASKS_QUEUE,
        )

        payload = {
            "user_id": user_id,
            "plan_date": plan_date,
            "nudge_slot": nudge_slot,
        }

        # Parse send_at_utc to a Unix timestamp for Cloud Tasks scheduling
        try:
            send_dt = datetime.fromisoformat(send_at_utc)
            if send_dt.tzinfo is None:
                send_dt = send_dt.replace(tzinfo=timezone.utc)
        except ValueError:
            # If the datetime is malformed, send in 1 hour as a safe fallback
            send_dt = datetime.now(timezone.utc) + timedelta(hours=1)

        eta = timestamp_pb2.Timestamp()
        eta.FromSeconds(int(send_dt.timestamp()))

        task: dict[str, Any] = {
            "http_request": {
                "http_method": tasks_v2.HttpMethod.POST,
                "url": f"{settings.BACKEND_INTERNAL_URL}/internal/daily-notify/send",
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps(payload).encode(),
                "oidc_token": {
                    "service_account_email": settings.SCHEDULER_SA_EMAIL,
                    "audience": settings.BACKEND_INTERNAL_URL,
                },
            },
            "schedule_time": eta,
        }

        created = client.create_task(parent=queue_path, task=task)
        return created.name

    try:
        task_name = await asyncio.to_thread(_enqueue)
        # Store the task name in daily_plans so it can be cancelled if needed
        await asyncio.to_thread(
            lambda: admin_firestore()
            .collection("users").document(user_id)
            .collection("daily_plans").document(plan_date)
            .update({f"{nudge_slot}.cloud_task_name": task_name})
        )
        logger.info("daily_notification: nudge task scheduled", {
            "user_id": user_id,
            "nudge_slot": nudge_slot,
            "send_at_utc": send_at_utc,
            "task_name": task_name,
        })
    except Exception as exc:
        logger.exception("daily_notification: failed to schedule nudge task", {
            "user_id": user_id,
            "nudge_slot": nudge_slot,
            "error": str(exc),
        })


# Context extraction helpers 
def _extract_topic_keywords(queries: list[dict]) -> list[str]:
    """Extract topic keywords from recent queries for RSS search."""
    keywords: set[str] = set()
    topic_word_map = {
        "nutrition": ["nutrition", "food", "eat", "diet", "calories", "protein", "carbs", "fat", "meal"],
        "workout": ["workout", "gym", "exercise", "run", "lift", "training", "cardio", "weights"],
        "sleep": ["sleep", "insomnia", "tired", "rest", "bedtime", "fatigue"],
        "hydration": ["water", "hydrat", "thirst"],
        "mindfulness": ["stress", "anxiety", "meditat", "mindful", "mental"],
    }
    for query in queries:
        text = query.get("text", "").lower()
        for topic, words in topic_word_map.items():
            if any(w in text for w in words):
                keywords.add(topic)
    return list(keywords) if keywords else []


def _extract_topics_from_plans(recent_plans: list[dict]) -> list[str]:
    """Extract topic names from the last 2 daily plans to avoid repetition."""
    topics: list[str] = []
    for plan in recent_plans:
        for slot in ("morning_nudge", "evening_nudge"):
            nudge = plan.get(slot, {})
            topic = nudge.get("topic")
            if topic and topic not in topics:
                topics.append(topic)
    return topics


# Timezone helpers 
def _local_now_iso(user_timezone: str) -> str:
    """Return the current datetime in the user's timezone as an ISO string."""
    try:
        tz = ZoneInfo(user_timezone)
        return datetime.now(tz).isoformat()
    except (ZoneInfoNotFoundError, Exception):
        return datetime.now(timezone.utc).isoformat()


def _local_hhmm_to_utc(hhmm: str, user_timezone: str) -> str:
    """Convert today's "HH:MM" in user_timezone to a UTC ISO datetime string."""
    try:
        tz = ZoneInfo(user_timezone)
        h, m = int(hhmm.split(":")[0]), int(hhmm.split(":")[1])
        local_now = datetime.now(tz)
        local_target = local_now.replace(hour=h, minute=m, second=0, microsecond=0)
        # If the target time has already passed today, schedule for tomorrow
        if local_target <= local_now:
            local_target += timedelta(days=1)
        return local_target.astimezone(timezone.utc).isoformat()
    except Exception:
        # Fallback: UTC now + 1 hour
        return (datetime.now(timezone.utc) + timedelta(hours=1)).isoformat()
