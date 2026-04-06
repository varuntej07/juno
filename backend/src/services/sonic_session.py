"""
SonicRealtimeSession — bidirectional voice streaming with AWS Bedrock Nova Sonic.

Threading model:
  asyncio event loop
      │  _input_queue (asyncio.Queue) ← fed by WebSocket message handlers
      │
      ▼ _bridge_task (asyncio coroutine)
  threading.Queue (_sync_queue)  ← consumed by boto3 sync generator
      │
      ▼  boto3 thread (ThreadPoolExecutor)
  invoke_model_with_bidirectional_stream → Nova Sonic
      │
      ▼ response events put back via run_coroutine_threadsafe
  asyncio event loop → send() to Flutter WebSocket
"""

from __future__ import annotations

import asyncio
import json
import queue as sync_queue_mod
import threading
from base64 import b64decode, b64encode
from collections.abc import Callable
from typing import Any
from uuid import uuid4

import boto3
from botocore.config import Config

from ..config.settings import settings
from ..lib.logger import logger
from ..shared.protocol import (
    AssistantAudioChunkMsg,
    AssistantTextDeltaMsg,
    AssistantTextFinalMsg,
    ErrorMsg,
    ServerMessage,
    SessionEndedMsg,
    SessionReadyMsg,
    SessionStateMsg,
    ToolCallMsg,
    ToolResultMsg,
)
from ..shared.tools import sonic_tool_configuration
from .tool_executor import ToolExecutor

SendFn = Callable[[ServerMessage], None]


class SonicRealtimeSession:
    def __init__(
        self,
        *,
        user_id: str,
        voice_id: str | None = None,
        system_prompt: str | None = None,
        send: SendFn,
        tool_executor: ToolExecutor,
    ) -> None:
        self._session_id = str(uuid4())
        self._prompt_name = f"prompt-{self._session_id}"
        self._audio_content_name = f"audio-{self._session_id}"

        self._user_id = user_id
        self._voice_id = voice_id or settings.BEDROCK_SONIC_VOICE
        self._system_prompt = system_prompt or settings.JUNO_DEFAULT_SYSTEM_PROMPT
        self._send = send
        self._tool_executor = tool_executor

        # Async ↔ sync bridges
        self._loop = asyncio.get_event_loop()
        self._input_queue: asyncio.Queue[dict[str, Any] | None] = asyncio.Queue()
        self._sync_queue: sync_queue_mod.Queue[bytes | None] = sync_queue_mod.Queue()

        # State
        self._accumulated_text: list[str] = []
        self._ended_input = False
        self._cancelled = False
        self._processing_task: asyncio.Task[None] | None = None

        # boto3 client (created fresh per session to avoid sharing state across threads)
        self._bedrock = boto3.client(
            "bedrock-runtime",
            region_name=settings.AWS_REGION,
            config=Config(
                read_timeout=300,
                connect_timeout=10,
                retries={"max_attempts": 0},
            ),
        )

    @property
    def id(self) -> str:
        return self._session_id

    # ─── Public interface (called from WebSocket handler) ────────────────────

    async def start(self) -> None:
        """Kick off the Nova Sonic session. Non-blocking — processing runs in background."""
        self._enqueue_start_events()

        # Bridge: drain asyncio queue → sync queue so boto3 generator can consume it
        asyncio.create_task(self._bridge_to_sync(), name=f"bridge-{self._session_id}")

        # Launch boto3 session in thread pool
        self._processing_task = asyncio.create_task(
            self._run_in_thread(), name=f"sonic-{self._session_id}"
        )

        self._send(SessionReadyMsg(sessionId=self._session_id))
        self._send(SessionStateMsg(
            sessionId=self._session_id,
            payload={"state": "listening"},
        ))

    def send_audio_chunk(self, audio_base64: str) -> None:
        if self._ended_input or self._cancelled:
            return
        self._input_queue.put_nowait({
            "event": {
                "audioInput": {
                    "promptName": self._prompt_name,
                    "contentName": self._audio_content_name,
                    "content": audio_base64,
                }
            }
        })

    def send_text_input(self, text: str) -> None:
        if self._ended_input or self._cancelled:
            return
        content_name = f"text-{uuid4()}"
        self._input_queue.put_nowait({
            "event": {
                "contentStart": {
                    "promptName": self._prompt_name,
                    "contentName": content_name,
                    "type": "TEXT",
                    "interactive": True,
                    "role": "USER",
                    "textInputConfiguration": {"mediaType": "text/plain"},
                }
            }
        })
        self._input_queue.put_nowait({
            "event": {
                "textInput": {
                    "promptName": self._prompt_name,
                    "contentName": content_name,
                    "content": text,
                }
            }
        })
        self._input_queue.put_nowait({
            "event": {
                "contentEnd": {
                    "promptName": self._prompt_name,
                    "contentName": content_name,
                }
            }
        })

    def send_ocr_context(self, text: str) -> None:
        if self._ended_input or self._cancelled:
            return
        content_name = f"ocr-{uuid4()}"
        self._input_queue.put_nowait({
            "event": {
                "contentStart": {
                    "promptName": self._prompt_name,
                    "contentName": content_name,
                    "type": "TEXT",
                    "interactive": False,
                    "role": "SYSTEM",
                    "textInputConfiguration": {"mediaType": "text/plain"},
                }
            }
        })
        self._input_queue.put_nowait({
            "event": {
                "textInput": {
                    "promptName": self._prompt_name,
                    "contentName": content_name,
                    "content": f"OCR context from the user camera scan:\n{text}",
                }
            }
        })
        self._input_queue.put_nowait({
            "event": {
                "contentEnd": {
                    "promptName": self._prompt_name,
                    "contentName": content_name,
                }
            }
        })

    def end_input(self) -> None:
        if self._ended_input or self._cancelled:
            return
        self._ended_input = True
        self._send(SessionStateMsg(
            sessionId=self._session_id,
            payload={"state": "processing"},
        ))
        self._input_queue.put_nowait({
            "event": {"contentEnd": {
                "promptName": self._prompt_name,
                "contentName": self._audio_content_name,
            }}
        })
        self._input_queue.put_nowait({
            "event": {"promptEnd": {"promptName": self._prompt_name}}
        })
        self._input_queue.put_nowait({
            "event": {"sessionEnd": {}}
        })
        self._input_queue.put_nowait(None)  # sentinel → close sync queue

    async def cancel(self) -> None:
        self._cancelled = True
        self._input_queue.put_nowait(None)
        if self._processing_task and not self._processing_task.done():
            self._processing_task.cancel()
            try:
                await self._processing_task
            except (asyncio.CancelledError, Exception):
                pass

    # ─── Session init events ─────────────────────────────────────────────────

    def _enqueue_start_events(self) -> None:
        self._input_queue.put_nowait({
            "event": {
                "sessionStart": {
                    "inferenceConfiguration": {
                        "maxTokens": settings.VOICE_GATEWAY_INPUT_MAX_TOKENS,
                        "topP": settings.VOICE_GATEWAY_TOP_P,
                        "temperature": settings.VOICE_GATEWAY_TEMPERATURE,
                    }
                }
            }
        })
        self._input_queue.put_nowait({
            "event": {"promptStart": {
                "promptName": self._prompt_name,
                "textOutputConfiguration": {"mediaType": "text/plain"},
                "audioOutputConfiguration": {
                    "mediaType": "audio/lpcm",
                    "sampleRateHertz": settings.VOICE_GATEWAY_SAMPLE_RATE_HZ,
                    "sampleSizeBits": 16,
                    "channelCount": 1,
                    "voiceId": self._voice_id,
                    "encoding": "base64",
                },
                "toolUseOutputConfiguration": {"mediaType": "application/json"},
                "toolConfiguration": sonic_tool_configuration(),
            }}
        })
        # System prompt
        sys_content = f"sys-{self._session_id}"
        self._input_queue.put_nowait({
            "event": {"contentStart": {
                "promptName": self._prompt_name,
                "contentName": sys_content,
                "type": "TEXT",
                "interactive": False,
                "role": "SYSTEM",
                "textInputConfiguration": {"mediaType": "text/plain"},
            }}
        })
        self._input_queue.put_nowait({
            "event": {"textInput": {
                "promptName": self._prompt_name,
                "contentName": sys_content,
                "content": self._system_prompt,
            }}
        })
        self._input_queue.put_nowait({
            "event": {"contentEnd": {
                "promptName": self._prompt_name,
                "contentName": sys_content,
            }}
        })
        # Audio input stream open
        self._input_queue.put_nowait({
            "event": {"contentStart": {
                "promptName": self._prompt_name,
                "contentName": self._audio_content_name,
                "type": "AUDIO",
                "interactive": True,
                "role": "USER",
                "audioInputConfiguration": {
                    "mediaType": "audio/lpcm",
                    "sampleRateHertz": settings.VOICE_GATEWAY_SAMPLE_RATE_HZ,
                    "sampleSizeBits": 16,
                    "channelCount": 1,
                    "encoding": "base64",
                    "audioType": "SPEECH",
                },
            }}
        })

    # ─── Async → sync bridge ─────────────────────────────────────────────────

    async def _bridge_to_sync(self) -> None:
        """Drain the asyncio input queue into the threading.Queue for boto3."""
        while True:
            item = await self._input_queue.get()
            if item is None:
                self._sync_queue.put(None)  # sentinel
                break
            payload_bytes = json.dumps(item).encode()
            self._sync_queue.put(payload_bytes)

    def _sync_input_generator(self):
        """Synchronous generator consumed by boto3 inside the worker thread."""
        while True:
            item = self._sync_queue.get()
            if item is None:
                return
            yield {"chunk": {"bytes": item}}

    # ─── Thread worker ───────────────────────────────────────────────────────

    async def _run_in_thread(self) -> None:
        """Run the blocking boto3 session in a thread pool executor."""
        loop = asyncio.get_running_loop()
        try:
            await loop.run_in_executor(None, self._blocking_session, loop)
        except Exception as exc:
            if not self._cancelled:
                logger.error("Sonic session thread error", {"error": str(exc), "session": self._session_id})
                self._send(ErrorMsg(sessionId=self._session_id, message=str(exc)))
        finally:
            final_text = " ".join(self._accumulated_text).strip()
            if final_text:
                self._send(AssistantTextFinalMsg(
                    sessionId=self._session_id,
                    text=final_text,
                ))
            self._send(SessionEndedMsg(sessionId=self._session_id))

    def _blocking_session(self, loop: asyncio.AbstractEventLoop) -> None:
        """Runs entirely in a worker thread. Sends events back via run_coroutine_threadsafe."""
        response = self._bedrock.invoke_model_with_bidirectional_stream(
            modelId=settings.BEDROCK_SONIC_MODEL_ID,
            body=self._sync_input_generator(),
        )

        for raw_event in response.get("body", []):
            if self._cancelled:
                break
            self._handle_stream_event(raw_event, loop)

    def _handle_stream_event(
        self,
        raw_event: dict[str, Any],
        loop: asyncio.AbstractEventLoop,
    ) -> None:
        """Parse a single Nova Sonic stream event and forward to Flutter."""
        # Check for error events first
        for err_key in (
            "validationException",
            "modelStreamErrorException",
            "internalServerException",
            "throttlingException",
            "serviceUnavailableException",
            "modelTimeoutException",
        ):
            if err_key in raw_event:
                msg = raw_event[err_key].get("message", f"Bedrock error: {err_key}")
                raise RuntimeError(msg)

        chunk = raw_event.get("chunk", {})
        raw_bytes = chunk.get("bytes", b"")
        if not raw_bytes:
            return

        try:
            event_data: dict[str, Any] = json.loads(raw_bytes)
        except json.JSONDecodeError:
            return

        event = event_data.get("event", {})

        # Text output
        if "textOutput" in event:
            text_event = event["textOutput"]
            if text_event.get("role") != "USER":
                text = text_event.get("content", "")
                if text:
                    self._accumulated_text.append(text)
                    self._thread_send(AssistantTextDeltaMsg(
                        sessionId=self._session_id,
                        text=text,
                    ), loop)
                    self._thread_send(SessionStateMsg(
                        sessionId=self._session_id,
                        payload={"state": "speaking"},
                    ), loop)

        # Audio output
        elif "audioOutput" in event:
            audio_event = event["audioOutput"]
            audio_content = audio_event.get("content", "")
            if audio_content:
                self._thread_send(AssistantAudioChunkMsg(
                    sessionId=self._session_id,
                    audioBase64=audio_content,
                    mimeType="audio/lpcm",
                    sampleRateHertz=settings.VOICE_GATEWAY_SAMPLE_RATE_HZ,
                ), loop)

        # Tool use
        elif "toolUse" in event:
            tool_event = event["toolUse"]
            tool_name = tool_event.get("toolName", "")
            content_raw = tool_event.get("content", "{}")
            content_id = tool_event.get("contentId", "")

            try:
                tool_input = json.loads(content_raw) if isinstance(content_raw, str) else content_raw
            except json.JSONDecodeError:
                tool_input = {"raw": content_raw}

            self._thread_send(ToolCallMsg(
                sessionId=self._session_id,
                toolName=tool_name,
                payload=tool_input,
            ), loop)

            # Execute tool synchronously from the thread (bridged back to asyncio)
            try:
                future = asyncio.run_coroutine_threadsafe(
                    self._tool_executor.execute(tool_name, tool_input),
                    loop,
                )
                result = future.result(timeout=30)
            except Exception as exc:
                logger.error("Tool error in Sonic session", {"tool": tool_name, "error": str(exc)})
                result = {"error": str(exc)}

            self._thread_send(ToolResultMsg(
                sessionId=self._session_id,
                toolName=tool_name,
                payload=result,
            ), loop)

            # Feed tool result back into Nova Sonic stream
            result_content_name = f"tool-result-{content_id}"
            self._sync_queue.put(json.dumps({
                "event": {"contentStart": {
                    "promptName": self._prompt_name,
                    "contentName": result_content_name,
                    "type": "TOOL",
                    "interactive": False,
                    "role": "TOOL",
                    "toolResultInputConfiguration": {
                        "mediaType": "application/json",
                        "toolUseId": content_id,
                        "toolName": tool_name,
                    },
                }}
            }).encode())
            self._sync_queue.put(json.dumps({
                "event": {"toolResult": {
                    "promptName": self._prompt_name,
                    "contentName": result_content_name,
                    "content": json.dumps(result),
                }}
            }).encode())
            self._sync_queue.put(json.dumps({
                "event": {"contentEnd": {
                    "promptName": self._prompt_name,
                    "contentName": result_content_name,
                }}
            }).encode())

        # Completion
        elif "completionEnd" in event:
            return  # _run_in_thread finalises after the loop

    def _thread_send(self, message: ServerMessage, loop: asyncio.AbstractEventLoop) -> None:
        """Thread-safe: schedule a WebSocket send back on the asyncio loop."""
        asyncio.run_coroutine_threadsafe(
            self._async_send(message), loop
        )

    async def _async_send(self, message: ServerMessage) -> None:
        self._send(message)
