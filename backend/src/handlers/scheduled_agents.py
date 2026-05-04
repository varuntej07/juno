"""
HTTP handlers for the scheduled domain agents pipeline.

Two endpoints:
  POST /internal/agents/tick
    → Fan-out: load active users, enqueue one Cloud Task per (agent, user).
      Called by Cloud Scheduler on a recurring schedule.

  POST /internal/agents/{agentId}/run/{userId}
    → Execute one agent for one user: fetch data, build notification, send FCM.
      Called by Cloud Tasks (enqueued by the tick handler).

Both endpoints are internal and require OIDC verification via the shared
_verify_scheduler_token dependency in main.py.
"""

from __future__ import annotations

from typing import Any

from ..agents.orchestrator import orchestrate_all_agents, run_agent_for_user
from ..lib.logger import logger


async def handle_agents_tick(body: dict[str, Any]) -> dict[str, Any]:
    """Fan-out all scheduled agents to all active users.

    Optional body field:
      agent_ids: list[str]  — run only these agents (defaults to all)
    """
    agent_ids = body.get("agent_ids") or None
    result = await orchestrate_all_agents(agent_ids=agent_ids)
    logger.info("handle_agents_tick: complete", result)
    return result


async def handle_agent_run(agent_id: str, user_id: str) -> dict[str, Any]:
    """Run one agent for one user and send a push notification."""
    await run_agent_for_user(agent_id, user_id)
    return {"ok": True, "agent_id": agent_id, "user_id": user_id}
