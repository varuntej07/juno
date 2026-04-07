"""
POST /scheduler/tick — find due reminders and send FCM push notifications.
Called by a cron job (EventBridge, Cloud Scheduler, etc.) every minute.
"""

from __future__ import annotations

import json
from typing import Any

from firebase_admin import messaging

from ..lib.logger import logger
from ..services.firebase import admin_messaging
from ..services.google_calendar_connector import GoogleCalendarConnector
from ..services.tool_executor import fetch_due_reminders, list_user_fcm_tokens, mark_reminder_fired


def _json(status: int, payload: dict[str, Any]) -> dict[str, Any]:
    return {
        "statusCode": status,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(payload),
    }


def _send_reminder_notification(
    user_id: str,
    reminder_id: str,
    data: dict[str, Any],
) -> messaging.BatchResponse | None:
    tokens = list_user_fcm_tokens(user_id)
    if not tokens:
        return None

    message = messaging.MulticastMessage(
        tokens=tokens,
        notification=messaging.Notification(
            title="Juno Reminder",
            body=str(data.get("message", "Reminder due now")),
        ),
        data={
            "type": "reminder",
            "reminder_id": reminder_id,
            "user_id": user_id,
            "created_via": str(data.get("created_via", "voice")),
        },
        android=messaging.AndroidConfig(priority="high"),
        apns=messaging.APNSConfig(
            payload=messaging.APNSPayload(
                aps=messaging.Aps(sound="default", category="JUNO_REMINDER"),
            )
        ),
    )
    return admin_messaging().send_each_for_multicast(message)


async def handle_scheduler_tick(event: dict[str, Any] | None = None) -> dict[str, Any]:
    try:
        renewed_channels = GoogleCalendarConnector.renew_expiring_channels(limit=10)
        synced_calendars = GoogleCalendarConnector.process_pending_sync_jobs(limit=20)

        due = fetch_due_reminders()
        delivered = 0

        for item in due:
            user_id = item["userId"]
            reminder_id = item["reminderId"]
            data = item["data"]

            try:
                result = _send_reminder_notification(user_id, reminder_id, data)
                if result and result.success_count > 0:
                    mark_reminder_fired(user_id, reminder_id)
                    delivered += 1
                    logger.info("Reminder delivered", {
                        "user_id": user_id,
                        "reminder_id": reminder_id,
                    })
            except Exception as exc:
                logger.error("Failed to deliver reminder", {
                    "user_id": user_id,
                    "reminder_id": reminder_id,
                    "error": str(exc),
                })

        return _json(200, {
            "scanned": len(due),
            "delivered": delivered,
            "calendar_syncs": synced_calendars,
            "renewed_calendar_channels": renewed_channels,
        })

    except Exception as exc:
        logger.error("Scheduler tick failed", {"error": str(exc)})
        return _json(500, {"error": "Internal server error"})
