"""
LiveKit data-channel message contracts sent from the agent to the Flutter client.
Audio is carried over WebRTC tracks — only text/state events use the data channel.
"""

from typing import Literal

from pydantic import BaseModel


class SessionStateMsg(BaseModel):
    type: Literal["session.state"] = "session.state"
    state: Literal["listening", "thinking", "speaking"]


class AssistantTextMsg(BaseModel):
    type: Literal["assistant.text"] = "assistant.text"
    text: str
    is_final: bool = True


class ErrorMsg(BaseModel):
    type: Literal["error"] = "error"
    message: str


class SessionEndedMsg(BaseModel):
    type: Literal["session.ended"] = "session.ended"
