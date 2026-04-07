"""
ClaudeClient — multi-turn conversation with tool-use loop via Anthropic SDK.
Used by the text /chat endpoint; Nova Sonic handles voice natively.
"""

from __future__ import annotations

import asyncio
import time
from typing import Any

import anthropic

from ..config.settings import settings
from ..lib.logger import logger
from ..shared.tools import claude_tool_definitions
from .tool_executor import ToolExecutor

_MAX_TURNS = 6

# get_user_context is a "fetch everything" mega-tool that was causing double-fetches
# (chat.py used to pre-fetch it, then Claude called it again).  For text chat, Claude
# should call the individual focused tools (list_reminders, get_upcoming_events,
# query_memory) so it only fetches what's actually needed.
_CHAT_EXCLUDED_TOOLS = {"get_user_context"}


class ClaudeClient:
    def __init__(self, tool_executor: ToolExecutor) -> None:
        self._tool_executor = tool_executor
        self._client = anthropic.AsyncAnthropic(api_key=settings.ANTHROPIC_API_KEY)

    async def send_text_turn(
        self,
        *,
        system_prompt: str,
        user_text: str,
        history: list[dict[str, Any]] | None = None,
    ) -> dict[str, Any]:
        """
        Run a full multi-turn Claude conversation until a text response
        with no tool calls is produced (or max turns exceeded).

        Args:
            history: Optional list of prior turns [{role, content}] to prepend
                     before the current user_text. Enables multi-turn context
                     across HTTP requests. Must alternate user/assistant roles
                     and end before the current user turn.

        Returns:
            {"text": str, "tool_names": list[str]}
        """
        tools = [t for t in claude_tool_definitions() if t["name"] not in _CHAT_EXCLUDED_TOOLS]

        # Build message list: prior history + current user turn.
        # Anthropic requires messages to alternate roles starting with "user".
        prior: list[dict[str, Any]] = history or []
        messages: list[dict[str, Any]] = [
            *prior,
            {"role": "user", "content": user_text},
        ]
        accumulated_text: list[str] = []
        tool_names_used: list[str] = []

        logger.info("Claude: starting conversation", {
            "model": settings.ANTHROPIC_MODEL,
            "max_tokens": settings.ANTHROPIC_MAX_TOKENS,
            "user_text_len": len(user_text),
            "history_turns": len(prior),
        })

        for turn in range(_MAX_TURNS):
            turn_start = time.monotonic()
            logger.debug(f"Claude: API call (turn {turn + 1}/{_MAX_TURNS})", {
                "model": settings.ANTHROPIC_MODEL,
                "messages_in_history": len(messages),
            })

            try:
                response = await self._client.messages.create(
                    model=settings.ANTHROPIC_MODEL,
                    max_tokens=settings.ANTHROPIC_MAX_TOKENS,
                    system=system_prompt,
                    tools=tools,  # type: ignore[arg-type]
                    messages=messages,  # type: ignore[arg-type]
                )
            except Exception as exc:
                logger.exception("Claude: API call failed", {
                    "turn": turn + 1,
                    "error_type": type(exc).__name__,
                    "error": str(exc),
                })
                raise

            turn_ms = int((time.monotonic() - turn_start) * 1000)
            logger.info(f"Claude: API response (turn {turn + 1})", {
                "model": settings.ANTHROPIC_MODEL,
                "stop_reason": response.stop_reason,
                "input_tokens": response.usage.input_tokens,
                "output_tokens": response.usage.output_tokens,
                "duration_ms": turn_ms,
            })

            # Collect text from this turn
            for block in response.content:
                if block.type == "text":
                    accumulated_text.append(block.text)

            # No tool calls → done
            if response.stop_reason != "tool_use":
                break

            # Collect all tool_use blocks from this turn
            tool_use_blocks = [b for b in response.content if b.type == "tool_use"]

            # Execute all tool calls for this turn concurrently
            async def _run_tool(block: Any) -> dict[str, Any]:
                tool_start = time.monotonic()
                logger.info("Claude: tool call", {
                    "tool": block.name,
                    "tool_use_id": block.id,
                    "turn": turn + 1,
                })
                try:
                    result = await self._tool_executor.execute(block.name, block.input)
                    tool_ms = int((time.monotonic() - tool_start) * 1000)
                    logger.info("Claude: tool result", {
                        "tool": block.name,
                        "duration_ms": tool_ms,
                        "result_keys": list(result.keys()) if isinstance(result, dict) else "non-dict",
                    })
                except Exception as exc:
                    tool_ms = int((time.monotonic() - tool_start) * 1000)
                    logger.exception("Claude: tool execution error", {
                        "tool": block.name,
                        "error": str(exc),
                        "duration_ms": tool_ms,
                    })
                    result = {"error": str(exc)}
                tool_names_used.append(block.name)
                return {
                    "type": "tool_result",
                    "tool_use_id": block.id,
                    "content": str(result),
                }

            tool_results = await asyncio.gather(*[_run_tool(b) for b in tool_use_blocks])

            # Append assistant turn + tool results to history
            messages.append({"role": "assistant", "content": response.content})  # type: ignore[arg-type]
            messages.append({"role": "user", "content": list(tool_results)})
        else:
            logger.warn("Claude: max turns exceeded", {
                "max_turns": _MAX_TURNS,
                "tools_used": tool_names_used,
            })

        final_text = " ".join(accumulated_text).strip()
        logger.info("Claude: conversation complete", {
            "turns": min(turn + 1, _MAX_TURNS),
            "response_len": len(final_text),
            "tools_used": tool_names_used,
        })

        return {
            "text": final_text,
            "tool_names": tool_names_used,
        }
