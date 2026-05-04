"""
Base class for all scheduled domain agents (cricket, tech news, jobs, posts).
Each agent fetches fresh content, generates a push notification, and processes
user feedback to improve future nudges.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any

from google.cloud import firestore as fs
from datetime import datetime, timezone

from ..lib.logger import logger
from ..services.firebase import admin_firestore


class ScheduledAgent(ABC):
    """
    Abstract base for all scheduled domain agents.

    Subclasses implement:
      - fetch_data(user_config)      → raw content items
      - build_notification(...)      → title + body + chat_opener
      - agent_id property            → unique string identifier

    The base provides:
      - load_user_config()           → Firestore agent_config/{agent_id}
      - load_recent_feedback()       → last N interactions from agent_memory
      - save_interaction()           → write interaction after user reply
    """

    @property
    @abstractmethod
    def agent_id(self) -> str: ...

    @abstractmethod
    async def fetch_data(self, user_config: dict[str, Any]) -> list[dict[str, Any]]:
        """Fetch fresh content items. No LLM calls here — pure data."""
        ...

    @abstractmethod
    async def build_notification(
        self,
        content: list[dict[str, Any]],
        user_config: dict[str, Any],
        recent_feedback: list[dict[str, Any]],
    ) -> dict[str, str]:
        """
        Call the LLM to produce a push notification.
        Must return: {"title": str, "body": str, "chat_opener": str}
        """
        ...

    def _db(self) -> fs.Client:
        return admin_firestore()

    def _agent_config_ref(self, user_id: str) -> fs.DocumentReference:
        return (
            self._db()
            .collection("users")
            .document(user_id)
            .collection("agent_config")
            .document(self.agent_id)
        )

    def _interactions_ref(self, user_id: str) -> fs.CollectionReference:
        return (
            self._db()
            .collection("users")
            .document(user_id)
            .collection("agent_memory")
            .document(self.agent_id)
            .collection("interactions")
        )

    def _agent_state_ref(self, user_id: str) -> fs.DocumentReference:
        return (
            self._db()
            .collection("users")
            .document(user_id)
            .collection("agent_state")
            .document(self.agent_id)
        )

    async def load_user_config(self, user_id: str) -> dict[str, Any]:
        import asyncio
        snap = await asyncio.to_thread(lambda: self._agent_config_ref(user_id).get())
        config: dict[str, Any] = snap.to_dict() or {} if snap.exists else {}
        config.setdefault("enabled", True)
        return config

    async def load_recent_feedback(
        self, user_id: str, limit: int = 20
    ) -> list[dict[str, Any]]:
        import asyncio
        docs = await asyncio.to_thread(
            lambda: list(
                self._interactions_ref(user_id)
                .order_by("created_at", direction=fs.Query.DESCENDING)
                .limit(limit)
                .stream()
            )
        )
        return [d.to_dict() or {} for d in docs]

    async def save_interaction(
        self,
        user_id: str,
        nudge_id: str,
        content_source: str,
        content_topic: str,
        user_action: str,
        user_reply: str | None = None,
    ) -> None:
        import asyncio
        doc = {
            "nudge_id": nudge_id,
            "content_source": content_source,
            "content_topic": content_topic,
            "user_action": user_action,
            "user_reply": user_reply,
            "created_at": datetime.now(timezone.utc).isoformat(),
        }
        await asyncio.to_thread(
            lambda: self._interactions_ref(user_id).add(doc)
        )
        logger.info(
            f"Agent {self.agent_id}: interaction saved",
            {"user_id": user_id, "action": user_action, "topic": content_topic},
        )
