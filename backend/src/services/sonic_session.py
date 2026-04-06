"""
SonicRealtimeSession — bidirectional voice streaming with AWS Bedrock Nova Sonic.

Architecture:
  asyncio event loop
      │
      │  _input_queue (asyncio.Queue) ← fed by WebSocket message handlers
      │
      ▼  _send_loop (asyncio Task)
  stream.input_stream.send()  →  Nova Sonic
      │
      ▼  _recv_loop (asyncio Task)
  stream.output_stream (async iterator)
      │
      ▼  _handle_event (coroutine)
  send() callback → Flutter WebSocket
"""

from __future__ import annotations

import asyncio
import json
import time
from base64 import b64decode, b64encode
from collections.abc import Callable
from typing import Any
from uuid import uuid4

from aws_sdk_bedrock_runtime.client import BedrockRuntimeClient
from aws_sdk_bedrock_runtime.config import Config as BedrockConfig
from aws_sdk_bedrock_runtime.models import (
    BidirectionalInputPayloadPart,
    InvokeModelWithBidirectionalStreamInputChunk,
    InvokeModelWithBidirectionalStreamOperationInput,
    InvokeModelWithBidirectionalStreamOutputChunk,
    InvokeModelWithBidirectionalStreamOutputInternalServerException,
    InvokeModelWithBidirectionalStreamOutputModelStreamErrorException,
    InvokeModelWithBidirectionalStreamOutputModelTimeoutException,
    InvokeModelWithBidirectionalStreamOutputServiceUnavailableException,
    InvokeModelWithBidirectionalStreamOutputThrottlingException,
    InvokeModelWithBidirectionalStreamOutputValidationException,
)
from smithy_aws_core.identity.environment import EnvironmentCredentialsResolver

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

# Error event types that map to raised RuntimeErrors
_BEDROCK_STREAM_ERRORS = (
    InvokeModelWithBidirectionalStreamOutputInternalServerException,
    InvokeModelWithBidirectionalStreamOutputModelStreamErrorException,
    InvokeModelWithBidirectionalStreamOutputValidationException,
    InvokeModelWithBidirectionalStreamOutputThrottlingException,
    InvokeModelWithBidirectionalStreamOutputModelTimeoutException,
    InvokeModelWithBidirectionalStreamOutputServiceUnavailableException,
)


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

        # Unified outbound queue — fed by all public methods
        self._input_queue: asyncio.Queue[dict[str, Any] | None] = asyncio.Queue()

        # State
        self._accumulated_text: list[str] = []
        self._ended_input = False
        self._cancelled = False

        # Background tasks
        self._send_task: asyncio.Task[None] | None = None
        self._recv_task: asyncio.Task[None] | None = None
        self._stream = None

        # Counters for observability
        self._audio_chunks_in = 0
        self._audio_chunks_out = 0
        self._text_deltas_out = 0
        self._tool_calls = 0
        self._stream_events = 0

    @property
    def id(self) -> str:
        return self._session_id

    # ─── Public interface (called from WebSocket handler) ────────────────────

    async def start(self) -> None:
        """Open the Nova Sonic stream and start background send/recv tasks."""
        logger.info("Sonic: starting session", {
            "session_id": self._session_id,
            "user_id": self._user_id,
            "voice_id": self._voice_id,
            "model": settings.BEDROCK_SONIC_MODEL_ID,
            "region": settings.AWS_REGION,
        })

        config = BedrockConfig(
            endpoint_uri=f"https://bedrock-runtime.{settings.AWS_REGION}.amazonaws.com",
            region=settings.AWS_REGION,
            aws_credentials_identity_resolver=EnvironmentCredentialsResolver(),
        )
        client = BedrockRuntimeClient(config=config)

        logger.info("Sonic: invoking Bedrock bidirectional stream", {
            "session_id": self._session_id,
            "model": settings.BEDROCK_SONIC_MODEL_ID,
            "region": settings.AWS_REGION,
        })
        self._stream = await client.invoke_model_with_bidirectional_stream(
            InvokeModelWithBidirectionalStreamOperationInput(
                model_id=settings.BEDROCK_SONIC_MODEL_ID
            )
        )

        # Pre-fill queue with session setup events before tasks start
        self._enqueue_start_events()

        self._send_task = asyncio.create_task(
            self._send_loop(), name=f"sonic-send-{self._session_id}"
        )
        self._recv_task = asyncio.create_task(
            self._recv_loop(), name=f"sonic-recv-{self._session_id}"
        )

        self._send(SessionReadyMsg(sessionId=self._session_id))
        self._send(SessionStateMsg(
            sessionId=self._session_id,
            payload={"state": "listening"},
        ))

    def send_audio_chunk(self, audio_base64: str) -> None:
        if self._ended_input or self._cancelled:
            return
        self._audio_chunks_in += 1
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
        logger.info("Sonic: queuing text input", {
            "session_id": self._session_id,
            "text_len": len(text),
            "text_preview": text[:80],
        })
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
        logger.info("Sonic: end_input — signalling processing state", {
            "session_id": self._session_id,
            "audio_chunks_sent": self._audio_chunks_in,
        })
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
        self._input_queue.put_nowait(None)  # sentinel → close input stream

    async def cancel(self) -> None:
        logger.info("Sonic: cancelling session", {
            "session_id": self._session_id,
            "stream_events_processed": self._stream_events,
        })
        self._cancelled = True
        self._input_queue.put_nowait(None)  # unblock _send_loop if waiting

        tasks = [t for t in (self._send_task, self._recv_task) if t]
        for task in tasks:
            if not task.done():
                task.cancel()
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)

        if self._stream is not None:
            try:
                await self._stream.close()
            except Exception:
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

    # ─── Background tasks ────────────────────────────────────────────────────

    async def _send_loop(self) -> None:
        """Drain _input_queue and forward each event to Nova Sonic's input stream."""
        try:
            while True:
                item = await self._input_queue.get()
                if item is None:
                    await self._stream.input_stream.close()
                    break
                payload_bytes = json.dumps(item).encode()
                event = InvokeModelWithBidirectionalStreamInputChunk(
                    value=BidirectionalInputPayloadPart(bytes_=payload_bytes)
                )
                await self._stream.input_stream.send(event)
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            if not self._cancelled:
                logger.exception("Sonic: send loop error", {
                    "session_id": self._session_id,
                    "error_type": type(exc).__name__,
                    "error": str(exc),
                })

    async def _recv_loop(self) -> None:
        """Consume Nova Sonic's output stream and dispatch events."""
        start_ts = time.monotonic()
        try:
            _, output_stream = await self._stream.await_output()

            async for output_event in output_stream:
                if self._cancelled:
                    break
                self._stream_events += 1

                # Surface Bedrock-level stream errors as exceptions
                if isinstance(output_event, _BEDROCK_STREAM_ERRORS):
                    err_type = type(output_event).__name__
                    msg = getattr(output_event.value, "message", str(output_event.value))
                    logger.error("Sonic: Bedrock stream error event", {
                        "session_id": self._session_id,
                        "error_type": err_type,
                        "message": msg,
                    })
                    raise RuntimeError(f"{err_type}: {msg}")

                if not isinstance(output_event, InvokeModelWithBidirectionalStreamOutputChunk):
                    continue

                raw = output_event.value.bytes_
                if not raw:
                    continue

                try:
                    event_data: dict[str, Any] = json.loads(raw)
                except json.JSONDecodeError as exc:
                    logger.warn("Sonic: failed to parse stream event JSON", {
                        "session_id": self._session_id,
                        "error": str(exc),
                        "raw_preview": raw[:100],
                    })
                    continue

                await self._handle_event(event_data)

            duration_ms = int((time.monotonic() - start_ts) * 1000)
            logger.info("Sonic: session completed", {
                "session_id": self._session_id,
                "duration_ms": duration_ms,
                "stream_events": self._stream_events,
                "audio_chunks_in": self._audio_chunks_in,
                "audio_chunks_out": self._audio_chunks_out,
                "text_deltas_out": self._text_deltas_out,
                "tool_calls": self._tool_calls,
            })

        except asyncio.CancelledError:
            raise
        except Exception as exc:
            duration_ms = int((time.monotonic() - start_ts) * 1000)
            if not self._cancelled:
                logger.exception("Sonic: session error", {
                    "session_id": self._session_id,
                    "error_type": type(exc).__name__,
                    "error": str(exc),
                    "duration_ms": duration_ms,
                })
                self._send(ErrorMsg(
                    sessionId=self._session_id,
                    message=f"[{type(exc).__name__}] {exc}",
                ))
        finally:
            final_text = " ".join(self._accumulated_text).strip()
            if final_text:
                logger.info("Sonic: sending final text", {
                    "session_id": self._session_id,
                    "text_len": len(final_text),
                    "text_preview": final_text[:100],
                })
                self._send(AssistantTextFinalMsg(
                    sessionId=self._session_id,
                    text=final_text,
                ))
            self._send(SessionEndedMsg(sessionId=self._session_id))

    async def _handle_event(self, event_data: dict[str, Any]) -> None:
        """Parse a single Nova Sonic event and forward to Flutter."""
        event = event_data.get("event", {})
        event_keys = list(event.keys())
        logger.debug(f"Sonic: stream event {event_keys}", {
            "session_id": self._session_id,
            "event_num": self._stream_events,
        })

        # Text output
        if "textOutput" in event:
            text_event = event["textOutput"]
            if text_event.get("role") != "USER":
                text = text_event.get("content", "")
                if text:
                    self._accumulated_text.append(text)
                    self._text_deltas_out += 1
                    logger.debug("Sonic: → textOutput delta", {
                        "session_id": self._session_id,
                        "text_preview": text[:60],
                    })
                    self._send(AssistantTextDeltaMsg(
                        sessionId=self._session_id,
                        text=text,
                    ))
                    self._send(SessionStateMsg(
                        sessionId=self._session_id,
                        payload={"state": "speaking"},
                    ))

        # Audio output
        elif "audioOutput" in event:
            audio_content = event["audioOutput"].get("content", "")
            if audio_content:
                self._audio_chunks_out += 1
                self._send(AssistantAudioChunkMsg(
                    sessionId=self._session_id,
                    audioBase64=audio_content,
                    mimeType="audio/lpcm",
                    sampleRateHertz=settings.VOICE_GATEWAY_SAMPLE_RATE_HZ,
                ))

        # Tool use
        elif "toolUse" in event:
            tool_event = event["toolUse"]
            tool_name = tool_event.get("toolName", "")
            content_raw = tool_event.get("content", "{}")
            content_id = tool_event.get("contentId", "")

            self._tool_calls += 1
            logger.info("Sonic: tool call received", {
                "session_id": self._session_id,
                "tool_name": tool_name,
                "content_id": content_id,
            })

            try:
                tool_input = json.loads(content_raw) if isinstance(content_raw, str) else content_raw
            except json.JSONDecodeError:
                tool_input = {"raw": content_raw}

            self._send(ToolCallMsg(
                sessionId=self._session_id,
                toolName=tool_name,
                payload=tool_input,
            ))

            tool_start = time.monotonic()
            try:
                result = await asyncio.wait_for(
                    self._tool_executor.execute(tool_name, tool_input),
                    timeout=30.0,
                )
                tool_ms = int((time.monotonic() - tool_start) * 1000)
                logger.info("Sonic: tool call completed", {
                    "session_id": self._session_id,
                    "tool_name": tool_name,
                    "duration_ms": tool_ms,
                })
            except Exception as exc:
                tool_ms = int((time.monotonic() - tool_start) * 1000)
                logger.exception("Sonic: tool execution error", {
                    "session_id": self._session_id,
                    "tool_name": tool_name,
                    "error": str(exc),
                    "duration_ms": tool_ms,
                })
                result = {"error": str(exc)}

            self._send(ToolResultMsg(
                sessionId=self._session_id,
                toolName=tool_name,
                payload=result,
            ))

            # Feed tool result back into Nova Sonic via the unified input queue
            result_content_name = f"tool-result-{content_id}"
            self._input_queue.put_nowait({
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
            })
            self._input_queue.put_nowait({
                "event": {"toolResult": {
                    "promptName": self._prompt_name,
                    "contentName": result_content_name,
                    "content": json.dumps(result),
                }}
            })
            self._input_queue.put_nowait({
                "event": {"contentEnd": {
                    "promptName": self._prompt_name,
                    "contentName": result_content_name,
                }}
            })

        # Completion end
        elif "completionEnd" in event:
            logger.info("Sonic: completionEnd received", {
                "session_id": self._session_id,
                "accumulated_text_len": sum(len(t) for t in self._accumulated_text),
            })
