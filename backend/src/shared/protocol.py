"""
WebSocket message contracts between Flutter client and voice gateway.
Mirrors src/shared/voice-protocol.ts exactly so Flutter never needs changes.
"""

from typing import Annotated, Any, Literal, Union

from pydantic import BaseModel, Field


# ─── Client -> Server ─────────────────────────────────────────────────────────

class SessionStartPayload(BaseModel):
    userId: str
    locale: str | None = None
    voiceId: str | None = None
    systemPrompt: str | None = None


class AudioPayload(BaseModel):
    audioBase64: str


class TextPayload(BaseModel):
    text: str


class SessionStartMsg(BaseModel):
    type: Literal["session.start"]
    payload: SessionStartPayload


class InputAudioMsg(BaseModel):
    type: Literal["input.audio"]
    payload: AudioPayload


class InputTextMsg(BaseModel):
    type: Literal["input.text"]
    payload: TextPayload


class InputOcrContextMsg(BaseModel):
    type: Literal["input.ocr_context"]
    payload: TextPayload


class InputEndMsg(BaseModel):
    type: Literal["input.end"]


class SessionCancelMsg(BaseModel):
    type: Literal["session.cancel"]


class PingMsg(BaseModel):
    type: Literal["ping"]


ClientMessage = Annotated[
    Union[
        SessionStartMsg,
        InputAudioMsg,
        InputTextMsg,
        InputOcrContextMsg,
        InputEndMsg,
        SessionCancelMsg,
        PingMsg,
    ],
    Field(discriminator="type"),
]


# ─── Server → Client ─────────────────────────────────────────────────────────

class SessionReadyMsg(BaseModel):
    type: Literal["session.ready"] = "session.ready"
    sessionId: str


class SessionStatePayload(BaseModel):
    state: Literal["listening", "processing", "speaking"]


class SessionStateMsg(BaseModel):
    type: Literal["session.state"] = "session.state"
    sessionId: str
    payload: SessionStatePayload


class AssistantTextDeltaMsg(BaseModel):
    type: Literal["assistant.text.delta"] = "assistant.text.delta"
    sessionId: str
    text: str


class AssistantTextFinalMsg(BaseModel):
    type: Literal["assistant.text.final"] = "assistant.text.final"
    sessionId: str
    text: str


class AssistantAudioChunkMsg(BaseModel):
    type: Literal["assistant.audio.chunk"] = "assistant.audio.chunk"
    sessionId: str
    audioBase64: str
    mimeType: str = "audio/lpcm"
    sampleRateHertz: int | None = None


class ToolCallMsg(BaseModel):
    type: Literal["tool.call"] = "tool.call"
    sessionId: str
    toolName: str
    payload: Any


class ToolResultMsg(BaseModel):
    type: Literal["tool.result"] = "tool.result"
    sessionId: str
    toolName: str
    payload: Any


class PongMsg(BaseModel):
    type: Literal["pong"] = "pong"
    sessionId: str


class ErrorMsg(BaseModel):
    type: Literal["error"] = "error"
    sessionId: str | None = None
    message: str


class SessionEndedMsg(BaseModel):
    type: Literal["session.ended"] = "session.ended"
    sessionId: str | None = None


ServerMessage = Union[
    SessionReadyMsg,
    SessionStateMsg,
    AssistantTextDeltaMsg,
    AssistantTextFinalMsg,
    AssistantAudioChunkMsg,
    ToolCallMsg,
    ToolResultMsg,
    PongMsg,
    ErrorMsg,
    SessionEndedMsg,
]
