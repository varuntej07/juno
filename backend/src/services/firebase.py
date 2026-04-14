"""
Firebase Admin SDK - lazy singleton
"""

from typing import Any

import firebase_admin
from firebase_admin import auth, firestore, messaging


def _app() -> firebase_admin.App:
    if firebase_admin._apps:
        return firebase_admin.get_app()
    return firebase_admin.initialize_app()


def admin_auth() -> Any:
    """Returns firebase_admin.auth module (bound to the initialized app)."""
    _app()
    return auth


def admin_firestore() -> Any:
    """Returns a google.cloud.firestore.Client for the default app."""
    return firestore.client(_app())


def admin_messaging() -> Any:
    """Returns firebase_admin.messaging module (bound to the initialized app)."""
    _app()
    return messaging
