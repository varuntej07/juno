"""
Central query logger.

Writes every user input to users/{uid}/queries/{id}.
Call this from every handler that receives user-generated text.

Never throws — a logging failure must never fail the request.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Literal

from .logger import logger

QueryType = Literal["chat", "voice", "nutrition_scan"]


async def log_query(
    user_id: str,
    query_type: QueryType,
    text: str,
    session_id: str | None = None,
) -> None:
    """Fire-and-forget write to users/{uid}/queries/{id}."""
    try:
        from ..services.firebase import admin_firestore
        db = admin_firestore()
        query_id = str(uuid.uuid4())
        doc: dict = {
            "text": text,
            "type": query_type,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
        if session_id:
            doc["session_id"] = session_id
        db.collection("users").document(user_id).collection("queries").document(query_id).set(doc)
    except Exception as exc:
        logger.warn("query_logger: write failed", {"user_id": user_id, "error": str(exc)})
