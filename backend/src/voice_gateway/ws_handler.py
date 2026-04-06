"""
FastAPI WebSocket handler for /voice/stream.
One session per connection. Dispatches client messages to SonicRealtimeSession.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from typing import Annotated

from fastapi import WebSocket, WebSocketDisconnect
from pydantic import TypeAdapter, ValidationError

from ..config.settings import settings
from ..lib.logger import logger
from ..services.firebase import admin_auth
from ..services.sonic_session import SonicRealtimeSession
from ..services.tool_executor import ToolExecutor
from ..shared.protocol import (
    ClientMessage,
    ErrorMsg,
    PongMsg,
    ServerMessage,
    SessionEndedMsg,
)

_client_message_adapter: TypeAdapter[ClientMessage] = TypeAdapter(
    Annotated[ClientMessage, ...]
)


@dataclass
class ConnectionContext:
    user_id: str
    session: SonicRealtimeSession | None = field(default=None)


async def _resolve_user_id(ws: WebSocket) -> str | None:
    """
    Auth strategy:
    1. Authorization: Bearer <firebase-id-token> → verify with Firebase Auth
    2. x-juno-user-id header (dev mode only, ENV != production)
    """
    auth_header = ws.headers.get("authorization", "")
    if auth_header.startswith("Bearer "):
        token = auth_header[7:]
        try:
            decoded = admin_auth().verify_id_token(token)
            return decoded["uid"]
        except Exception as exc:
            logger.warn("Firebase token verification failed", {"error": str(exc)})
            return None

    if not settings.is_production:
        fallback = ws.headers.get("x-juno-user-id", "")
        if fallback:
            logger.warn("Using dev fallback user id", {"user_id": fallback})
            return fallback

    return None


def _make_send(ws: WebSocket):
    """Return a sync callable that queues a WebSocket send (fire-and-forget)."""
    import asyncio

    def send(message: ServerMessage) -> None:
        payload = message.model_dump_json(exclude_none=True)
        try:
            loop = asyncio.get_event_loop()
            loop.create_task(ws.send_text(payload))
        except RuntimeError:
            pass  # loop closed — session shutting down

    return send


async def voice_stream_handler(ws: WebSocket) -> None:
    await ws.accept()

    user_id = await _resolve_user_id(ws)
    if not user_id:
        await ws.send_text(
            ErrorMsg(message="Unauthorized: valid Firebase ID token required.").model_dump_json()
        )
        await ws.close(code=1008)
        return

    logger.info("Voice gateway client connected", {"user_id": user_id})
    ctx = ConnectionContext(user_id=user_id)
    send = _make_send(ws)

    try:
        while True:
            raw = await ws.receive_text()

            try:
                data = json.loads(raw)
                msg = _client_message_adapter.validate_python(data)
            except (json.JSONDecodeError, ValidationError) as exc:
                await ws.send_text(
                    ErrorMsg(
                        sessionId=ctx.session.id if ctx.session else None,
                        message=f"Invalid message: {exc}",
                    ).model_dump_json()
                )
                continue

            match msg.type:
                case "session.start":
                    if ctx.session is not None:
                        await ws.send_text(
                            ErrorMsg(
                                sessionId=ctx.session.id,
                                message="Session already active. Cancel it first.",
                            ).model_dump_json()
                        )
                        continue

                    tool_executor = ToolExecutor(user_id)
                    ctx.session = SonicRealtimeSession(
                        user_id=user_id,
                        voice_id=msg.payload.voiceId,
                        system_prompt=msg.payload.systemPrompt,
                        send=send,
                        tool_executor=tool_executor,
                    )
                    await ctx.session.start()

                case "input.audio":
                    if ctx.session:
                        ctx.session.send_audio_chunk(msg.payload.audioBase64)

                case "input.text":
                    if ctx.session:
                        ctx.session.send_text_input(msg.payload.text)

                case "input.ocr_context":
                    if ctx.session:
                        ctx.session.send_ocr_context(msg.payload.text)

                case "input.end":
                    if ctx.session:
                        ctx.session.end_input()

                case "session.cancel":
                    if ctx.session:
                        await ctx.session.cancel()
                        ctx.session = None
                    await ws.send_text(SessionEndedMsg().model_dump_json())

                case "ping":
                    session_id = ctx.session.id if ctx.session else "unbound"
                    await ws.send_text(PongMsg(sessionId=session_id).model_dump_json())

    except WebSocketDisconnect:
        logger.info("Voice gateway client disconnected", {"user_id": user_id})
    except Exception as exc:
        logger.error("Voice gateway error", {"user_id": user_id, "error": str(exc)})
        try:
            await ws.send_text(
                ErrorMsg(
                    sessionId=ctx.session.id if ctx.session else None,
                    message=str(exc),
                ).model_dump_json()
            )
        except Exception:
            pass
    finally:
        if ctx.session:
            await ctx.session.cancel()
