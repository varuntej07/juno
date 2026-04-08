"""
FCM Token Registry — per-device token storage in Firestore.

Firestore path: users/{uid}/fcm_tokens/{token}

Each document:
  token         str   — FCM registration token (same as doc ID)
  platform      str   — "android" | "ios" | "web"
  registered_at str   — ISO UTC datetime, refreshed on every upsert

All functions are synchronous (Firebase Admin SDK is sync).
Call them via asyncio.to_thread() from async contexts.
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from ..lib.logger import logger
from .firebase import admin_firestore

_SUBCOLLECTION = "fcm_tokens"

# FCM error codes that indicate a token is permanently invalid.
INVALID_TOKEN_CODES = frozenset({
    "registration-token-not-registered",
    "invalid-registration-token",
    "invalid-argument",
})


def _tokens_ref(user_id: str):
    return (
        admin_firestore()
        .collection("users")
        .document(user_id)
        .collection(_SUBCOLLECTION)
    )


def register_token(user_id: str, token: str, platform: str) -> None:
    """Upsert an FCM token for a user device.

    Uses the token string as the document ID so registering the same
    token twice is a no-op (just updates ``registered_at``).

    Args:
        user_id:  Firestore user document ID.
        token:    FCM registration token from the device.
        platform: One of ``"android"``, ``"ios"``, ``"web"``.
    """
    now = datetime.now(UTC).isoformat()
    ref = _tokens_ref(user_id).document(token)
    doc = ref.get()

    if doc.exists:
        ref.update({"platform": platform, "registered_at": now})
        logger.debug("FCM token updated", {
            "user_id": user_id,
            "platform": platform,
            "token_preview": token[:20],
        })
    else:
        ref.set({
            "token": token,
            "platform": platform,
            "registered_at": now,
        })
        logger.info("FCM token registered", {
            "user_id": user_id,
            "platform": platform,
            "token_preview": token[:20],
        })


def get_user_tokens(user_id: str) -> list[dict[str, Any]]:
    """Return all FCM token documents for a user.

    Returns:
        List of dicts, each containing at minimum ``token`` and ``platform``.
        Returns empty list if the user has no registered devices.
    """
    docs = _tokens_ref(user_id).stream()
    tokens = [doc.to_dict() for doc in docs if doc.exists and doc.to_dict()]
    logger.debug("FCM tokens fetched", {
        "user_id": user_id,
        "token_count": len(tokens),
    })
    return tokens


def remove_invalid_tokens(user_id: str, tokens: list[str]) -> None:
    """Delete tokens that FCM reported as permanently invalid.

    Called automatically by ``notification_service.send_notification``
    whenever FCM returns an error code in ``INVALID_TOKEN_CODES``.

    Args:
        user_id: Firestore user document ID.
        tokens:  List of token strings to delete.
    """
    if not tokens:
        return
    ref = _tokens_ref(user_id)
    for token in tokens:
        ref.document(token).delete()
    logger.info("Invalid FCM tokens removed", {
        "user_id": user_id,
        "removed_count": len(tokens),
        "token_previews": [t[:20] for t in tokens],
    })
