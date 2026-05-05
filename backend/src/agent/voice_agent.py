"""
LiveKit voice agent using cascading architecture: 
Deepgram STT -> Claude LLM -> Cartesia TTS pipeline.

The worker connects to LiveKit Cloud and waits for participant joins.
When a Flutter client joins room "voice-{uid}", this agent starts a pipeline session.
"""

from __future__ import annotations

import asyncio
import json
import time
from contextlib import asynccontextmanager
from typing import AsyncIterator
from uuid import uuid4

from livekit import agents
from livekit.agents import AgentSession, JobContext, WorkerOptions, cli, function_tool
from livekit.agents import llm as lk_llm
from livekit.agents import stt as lk_stt
from livekit.agents import tts as lk_tts
from livekit.agents.voice.room_io import AudioInputOptions, RoomOptions
from livekit.plugins import anthropic, cartesia, deepgram, noise_cancellation, silero

from ..config.settings import settings
from ..lib.logger import logger
from ..services.tool_executor import ToolExecutor

_TOOL = settings.VOICE_TOOL_TIMEOUT_S


@asynccontextmanager
async def _voice_session_context(user_id: str, room_name: str) -> AsyncIterator[str]:
    session_id = str(uuid4())
    start = time.monotonic()
    logger.info("VoiceSession: started", {
        "session_id": session_id, "user_id": user_id, "room": room_name,
    })
    error: Exception | None = None
    try:
        yield session_id
    except Exception as exc:
        error = exc
        logger.exception("VoiceSession: unhandled error", {
            "session_id": session_id, "user_id": user_id,
            "error_type": type(exc).__name__, "error": str(exc),
        })
        raise
    finally:
        elapsed_ms = int((time.monotonic() - start) * 1000)
        logger.info("VoiceSession: closed", {
            "session_id": session_id, "user_id": user_id,
            "duration_ms": elapsed_ms,
            "error": str(error) if error else None,
        })


class BuddyAgent(agents.Agent):
    def __init__(self, user_id: str) -> None:
        super().__init__(instructions=settings.VOICE_PROMPT)
        self._user_id = user_id
        self._executor = ToolExecutor(user_id)

    def _ok(self, result: dict) -> str:
        return json.dumps(result)

    def _err(self, tool: str, exc: Exception) -> str:
        logger.exception("VoiceAgent: tool error", {"tool": tool, "user_id": self._user_id, "error": str(exc)})
        return json.dumps({"error": str(exc)})

    def _timeout(self, tool: str) -> str:
        logger.error("VoiceAgent: tool timed out", {"tool": tool, "user_id": self._user_id})
        return json.dumps({"error": "timed out — please try again"})

    # Reminders

    @function_tool
    async def set_reminder(self, message: str, delay_minutes: float, priority: str = "normal") -> str:
        """Set a reminder for the user that fires after delay_minutes minutes."""
        try:
            result = await asyncio.wait_for(
                self._executor.execute("set_reminder", {"message": message, "delay_minutes": delay_minutes, "priority": priority}),
                timeout=_TOOL,
            )
            return self._ok(result)
        except asyncio.TimeoutError:
            return self._timeout("set_reminder")
        except Exception as exc:
            return self._err("set_reminder", exc)

    @function_tool
    async def list_reminders(self, status_filter: str = "pending") -> str:
        """List the user's reminders. status_filter: 'pending', 'all', 'fired', 'dismissed'."""
        try:
            result = await asyncio.wait_for(
                self._executor.execute("list_reminders", {"status_filter": status_filter}),
                timeout=_TOOL,
            )
            return self._ok(result)
        except asyncio.TimeoutError:
            return self._timeout("list_reminders")
        except Exception as exc:
            return self._err("list_reminders", exc)

    @function_tool
    async def cancel_reminder(self, reminder_id: str) -> str:
        """Cancel (dismiss) a reminder by its ID."""
        try:
            result = await asyncio.wait_for(
                self._executor.execute("cancel_reminder", {"reminder_id": reminder_id}),
                timeout=_TOOL,
            )
            return self._ok(result)
        except asyncio.TimeoutError:
            return self._timeout("cancel_reminder")
        except Exception as exc:
            return self._err("cancel_reminder", exc)

    # Calendar

    @function_tool
    async def create_calendar_event(
        self,
        title: str,
        start_time: str,
        end_time: str = "",
        description: str = "",
        location: str = "",
    ) -> str:
        """Create a Google Calendar event. start_time and end_time are ISO 8601 strings."""
        try:
            result = await asyncio.wait_for(
                self._executor.execute("create_calendar_event", {
                    "title": title,
                    "start_time": start_time,
                    "end_time": end_time or None,
                    "description": description or None,
                    "location": location or None,
                }),
                timeout=_TOOL,
            )
            return self._ok(result)
        except asyncio.TimeoutError:
            return self._timeout("create_calendar_event")
        except Exception as exc:
            return self._err("create_calendar_event", exc)

    @function_tool
    async def get_upcoming_events(self, hours_ahead: int = 24, limit: int = 10) -> str:
        """Fetch upcoming Google Calendar events within the next hours_ahead hours."""
        try:
            result = await asyncio.wait_for(
                self._executor.execute("get_upcoming_events", {"hours_ahead": hours_ahead, "limit": limit}),
                timeout=_TOOL,
            )
            return self._ok(result)
        except asyncio.TimeoutError:
            return self._timeout("get_upcoming_events")
        except Exception as exc:
            return self._err("get_upcoming_events", exc)

    # Memory

    @function_tool
    async def store_memory(self, key: str, value: str, category: str) -> str:
        """Store a memory about the user. category: 'personal', 'preference', 'fact', etc."""
        try:
            result = await asyncio.wait_for(
                self._executor.execute("store_memory", {"key": key, "value": value, "category": category}),
                timeout=_TOOL,
            )
            return self._ok(result)
        except asyncio.TimeoutError:
            return self._timeout("store_memory")
        except Exception as exc:
            return self._err("store_memory", exc)

    @function_tool
    async def query_memory(self, query: str, category_filter: str = "all") -> str:
        """Search the user's memories. category_filter: 'all' or a specific category."""
        try:
            result = await asyncio.wait_for(
                self._executor.execute("query_memory", {"query": query, "category_filter": category_filter}),
                timeout=_TOOL,
            )
            return self._ok(result)
        except asyncio.TimeoutError:
            return self._timeout("query_memory")
        except Exception as exc:
            return self._err("query_memory", exc)

    # Nutrition

    @function_tool
    async def analyze_nutrition(
        self,
        ocr_text: str,
        quantity: float = 1.0,
        occasion: str = "",
        is_cheat_meal: bool = False,
    ) -> str:
        """Analyze nutrition information from a food label's OCR text."""
        try:
            result = await asyncio.wait_for(
                self._executor.execute("analyze_nutrition", {
                    "ocr_text": ocr_text,
                    "quantity": quantity,
                    "occasion": occasion or None,
                    "is_cheat_meal": is_cheat_meal,
                }),
                timeout=_TOOL,
            )
            return self._ok(result)
        except asyncio.TimeoutError:
            return self._timeout("analyze_nutrition")
        except Exception as exc:
            return self._err("analyze_nutrition", exc)

    # User context

    @function_tool
    async def get_user_context(
        self,
        include_memories: bool = True,
        include_reminders: bool = True,
        include_events: bool = True,
    ) -> str:
        """Get a snapshot of the user's memories, reminders, and upcoming calendar events."""
        try:
            result = await asyncio.wait_for(
                self._executor.execute("get_user_context", {
                    "include_memories": include_memories,
                    "include_reminders": include_reminders,
                    "include_events": include_events,
                }),
                timeout=_TOOL,
            )
            return self._ok(result)
        except asyncio.TimeoutError:
            return self._timeout("get_user_context")
        except Exception as exc:
            return self._err("get_user_context", exc)


async def entrypoint(ctx: JobContext) -> None:
    try:
        await asyncio.wait_for(ctx.connect(), timeout=settings.VOICE_CONNECT_TIMEOUT_S)
    except asyncio.TimeoutError:
        logger.error("VoiceAgent: room connect timed out", {"room": ctx.room.name})
        return
    except Exception as exc:
        logger.exception("VoiceAgent: room connect failed", {"room": ctx.room.name, "error": str(exc)})
        return

    user_id = ctx.room.name.removeprefix("voice-")
    if not user_id:
        logger.error("VoiceAgent: could not extract user_id from room name", {"room": ctx.room.name})
        return

    async with _voice_session_context(user_id, ctx.room.name) as session_id:
        stt_pipeline = lk_stt.FallbackAdapter(
            [
                deepgram.STT(model="nova-3", api_key=settings.DEEPGRAM_API_KEY),
                deepgram.STT(model="nova-2", api_key=settings.DEEPGRAM_API_KEY),
            ],
            attempt_timeout=10.0,
            max_retry_per_stt=1,
            retry_interval=0.5,
        )

        llm_pipeline = lk_llm.FallbackAdapter([
            anthropic.LLM(model=settings.ANTHROPIC_CHAT_MODEL, api_key=settings.ANTHROPIC_API_KEY),
            anthropic.LLM(model=settings.TIER_BALANCED, api_key=settings.ANTHROPIC_API_KEY),
        ])

        tts_pipeline = lk_tts.FallbackAdapter(
            [
                cartesia.TTS(api_key=settings.CARTESIA_API_KEY, model="sonic-3"),
                cartesia.TTS(api_key=settings.CARTESIA_API_KEY, model="sonic-2"),
            ],
            max_retry_per_tts=1,
        )

        session = AgentSession(
            stt=stt_pipeline,
            llm=llm_pipeline,
            tts=tts_pipeline,
            vad=silero.VAD.load(),
        )

        @session.on("agent_state_changed")
        def _on_state(ev) -> None:  # type: ignore[misc]
            logger.info("VoiceSession: state changed", {
                "session_id": session_id, "user_id": user_id,
                "state": str(ev.new_state),
            })

        @session.on("close")
        def _on_close(ev) -> None:  # type: ignore[misc]
            logger.info("VoiceSession: session close event", {
                "session_id": session_id, "user_id": user_id,
                "error": str(ev.error) if getattr(ev, "error", None) else None,
            })

        try:
            await session.start(
                room=ctx.room,
                agent=BuddyAgent(user_id=user_id),
                room_options=RoomOptions(
                    audio_input=AudioInputOptions(noise_cancellation=noise_cancellation.BVC()),
                ),
            )
        except Exception as exc:
            logger.exception("VoiceSession: session.start() failed", {
                "session_id": session_id, "user_id": user_id,
                "error_type": type(exc).__name__, "error": str(exc),
            })
            raise


if __name__ == "__main__":
    cli.run_app(
        WorkerOptions(
            entrypoint_fnc=entrypoint,
            max_retry=3,
        )
    )
