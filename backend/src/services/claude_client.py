"""
ClaudeClient — multi-turn conversation with tool-use loop via Anthropic SDK.
Used by the text /chat endpoint; Nova Sonic handles voice natively.
"""

from __future__ import annotations

from typing import Any

import anthropic

from ..config.settings import settings
from ..lib.logger import logger
from ..shared.tools import claude_tool_definitions
from .tool_executor import ToolExecutor

_MAX_TURNS = 6


class ClaudeClient:
    def __init__(self, tool_executor: ToolExecutor) -> None:
        self._tool_executor = tool_executor
        self._client = anthropic.Anthropic(api_key=settings.ANTHROPIC_API_KEY)

    async def send_text_turn(
        self,
        *,
        system_prompt: str,
        user_text: str,
    ) -> dict[str, Any]:
        """
        Run a full multi-turn Claude conversation until a text response
        with no tool calls is produced (or max turns exceeded).
        Returns {"text": str, "tool_names": list[str]}.
        """
        messages: list[dict[str, Any]] = [{"role": "user", "content": user_text}]
        accumulated_text: list[str] = []
        tool_names_used: list[str] = []

        for _ in range(_MAX_TURNS):
            response = self._client.messages.create(
                model=settings.ANTHROPIC_MODEL,
                max_tokens=settings.ANTHROPIC_MAX_TOKENS,
                system=system_prompt,
                tools=claude_tool_definitions(),  # type: ignore[arg-type]
                messages=messages,  # type: ignore[arg-type]
            )

            # Collect text from this turn
            for block in response.content:
                if block.type == "text":
                    accumulated_text.append(block.text)

            # No tool calls → done
            if response.stop_reason != "tool_use":
                break

            # Execute tool calls
            tool_results: list[dict[str, Any]] = []
            for block in response.content:
                if block.type != "tool_use":
                    continue

                tool_names_used.append(block.name)
                logger.info("Claude tool call", {"tool": block.name})

                try:
                    result = await self._tool_executor.execute(block.name, block.input)
                except Exception as exc:
                    logger.error("Tool execution error", {"tool": block.name, "error": str(exc)})
                    result = {"error": str(exc)}

                tool_results.append({
                    "type": "tool_result",
                    "tool_use_id": block.id,
                    "content": str(result),
                })

            # Append assistant turn + tool results to history
            messages.append({"role": "assistant", "content": response.content})  # type: ignore[arg-type]
            messages.append({"role": "user", "content": tool_results})
        else:
            logger.warn("Claude max turns exceeded", {"max_turns": _MAX_TURNS})

        return {
            "text": " ".join(accumulated_text).strip(),
            "tool_names": tool_names_used,
        }
