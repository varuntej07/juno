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
            uid = decoded["uid"]
            logger.info("WS auth: Firebase token verified", {"user_id": uid})
            return uid
        except Exception as exc:
            logger.error("WS auth: Firebase token verification failed", {
                "error": type(exc).__name__,
                "detail": str(exc),
            })
            return None

    if not settings.is_production:
        fallback = ws.headers.get("x-juno-user-id", "")
        if fallback:
            logger.warn("WS auth: using dev fallback x-juno-user-id header", {"user_id": fallback})
            return fallback
        logger.warn("WS auth: no Authorization header and no x-juno-user-id — rejecting")
        return None

    logger.error("WS auth: no Authorization header in production — rejecting")
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
    client_ip = ws.client.host if ws.client else "unknown"
    logger.info("WS: new connection attempt", {
        "client_ip": client_ip,
        "path": str(ws.url),
    })

    await ws.accept()

    user_id = await _resolve_user_id(ws)
    if not user_id:
        await ws.send_text(
            ErrorMsg(message="Unauthorized: valid Firebase ID token required.").model_dump_json()
        )
        await ws.close(code=1008)
        logger.warn("WS: connection rejected — unauthorized", {"client_ip": client_ip})
        return

    logger.info("WS: client connected", {"user_id": user_id, "client_ip": client_ip})
    ctx = ConnectionContext(user_id=user_id)
    send = _make_send(ws)
    msg_count = 0

    try:
        while True:
            raw = await ws.receive_text()
            msg_count += 1

            try:
                data = json.loads(raw)
                msg = _client_message_adapter.validate_python(data)
            except (json.JSONDecodeError, ValidationError) as exc:
                logger.warn("WS: invalid message received", {
                    "user_id": user_id,
                    "error": str(exc),
                    "raw_preview": raw[:120],
                })
                await ws.send_text(
                    ErrorMsg(
                        sessionId=ctx.session.id if ctx.session else None,
                        message=f"Invalid message: {exc}",
                    ).model_dump_json()
                )
                continue

            msg_type = msg.type
            logger.debug(f"WS: ← {msg_type}", {
                "user_id": user_id,
                "session_id": ctx.session.id if ctx.session else None,
                "msg_count": msg_count,
            })

            match msg_type:
                case "session.start":
                    if ctx.session is not None:
                        logger.warn("WS: session.start received but session already active", {
                            "user_id": user_id,
                            "session_id": ctx.session.id,
                        })
                        await ws.send_text(
                            ErrorMsg(
                                sessionId=ctx.session.id,
                                message="Session already active. Cancel it first.",
                            ).model_dump_json()
                        )
                        continue

                    logger.info("WS: starting new voice session", {
                        "user_id": user_id,
                        "voice_id": getattr(msg.payload, "voiceId", None),
                        "has_system_prompt": bool(getattr(msg.payload, "systemPrompt", None)),
                    })
                    tool_executor = ToolExecutor(user_id)
                    ctx.session = SonicRealtimeSession(
                        user_id=user_id,
                        voice_id=msg.payload.voiceId,
                        system_prompt=msg.payload.systemPrompt,
                        send=send,
                        tool_executor=tool_executor,
                    )
                    await ctx.session.start()
                    logger.info("WS: voice session started", {
                        "user_id": user_id,
                        "session_id": ctx.session.id,
                    })

                case "input.audio":
                    if ctx.session:
                        ctx.session.send_audio_chunk(msg.payload.audioBase64)

                case "input.text":
                    text_preview = (msg.payload.text or "")[:60]
                    logger.info("WS: text input received", {
                        "user_id": user_id,
                        "session_id": ctx.session.id if ctx.session else None,
                        "text_preview": text_preview,
                        "text_len": len(msg.payload.text or ""),
                    })
                    if ctx.session:
                        ctx.session.send_text_input(msg.payload.text)
                    else:
                        logger.warn("WS: input.text received but no active session", {"user_id": user_id})

                case "input.ocr_context":
                    if ctx.session:
                        ctx.session.send_ocr_context(msg.payload.text)

                case "input.end":
                    logger.info("WS: input.end — signalling end of input", {
                        "user_id": user_id,
                        "session_id": ctx.session.id if ctx.session else None,
                    })
                    if ctx.session:
                        ctx.session.end_input()

                case "session.cancel":
                    logger.info("WS: session.cancel received", {
                        "user_id": user_id,
                        "session_id": ctx.session.id if ctx.session else None,
                    })
                    if ctx.session:
                        await ctx.session.cancel()
                        ctx.session = None
                    await ws.send_text(SessionEndedMsg().model_dump_json())

                case "ping":
                    session_id = ctx.session.id if ctx.session else "unbound"
                    await ws.send_text(PongMsg(sessionId=session_id).model_dump_json())

    except WebSocketDisconnect as exc:
        logger.info("WS: client disconnected", {
            "user_id": user_id,
            "code": exc.code,
            "reason": exc.reason or "none",
            "messages_received": msg_count,
        })
    except Exception as exc:
        logger.exception("WS: unhandled exception in message loop", {
            "user_id": user_id,
            "session_id": ctx.session.id if ctx.session else None,
            "error": str(exc),
            "messages_received": msg_count,
        })
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
            logger.info("WS: cancelling active session on disconnect", {
                "user_id": user_id,
                "session_id": ctx.session.id,
            })
            await ctx.session.cancel()
