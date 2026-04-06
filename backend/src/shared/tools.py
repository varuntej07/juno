"""
Tool definitions shared between Nova Sonic and Claude.
Schema is identical to the TS version — Flutter and Bedrock never see a change.
"""

from typing import Any

# ─── Canonical tool specs ─────────────────────────────────────────────────────

TOOL_DEFINITIONS: list[dict[str, Any]] = [
    {
        "name": "set_reminder",
        "description": "Create a time-delayed reminder for the user.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "message": {"type": "string", "description": "What to remind the user about."},
                "delay_minutes": {
                    "type": "integer",
                    "description": "How many minutes from now to send the reminder.",
                    "minimum": 1,
                },
                "priority": {
                    "type": "string",
                    "enum": ["low", "normal", "urgent"],
                    "default": "normal",
                },
            },
            "required": ["message", "delay_minutes"],
        },
    },
    {
        "name": "list_reminders",
        "description": "List the user's reminders.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "status_filter": {
                    "type": "string",
                    "enum": ["pending", "fired", "all"],
                    "default": "pending",
                },
            },
        },
    },
    {
        "name": "cancel_reminder",
        "description": "Cancel (dismiss) a pending reminder.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "reminder_id": {"type": "string", "description": "ID of the reminder to cancel."},
            },
            "required": ["reminder_id"],
        },
    },
    {
        "name": "create_calendar_event",
        "description": "Create an event on the user's Google Calendar.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "title": {"type": "string"},
                "start_time": {"type": "string", "description": "ISO 8601 datetime string."},
                "end_time": {"type": "string", "description": "ISO 8601 datetime string. Defaults to 30 min after start."},
                "description": {"type": "string"},
                "location": {"type": "string"},
            },
            "required": ["title", "start_time"],
        },
    },
    {
        "name": "get_upcoming_events",
        "description": "Retrieve the user's upcoming calendar events.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "hours_ahead": {
                    "type": "integer",
                    "description": "How many hours ahead to look.",
                    "default": 24,
                },
            },
        },
    },
    {
        "name": "store_memory",
        "description": "Persist a fact, preference, or habit about the user for future context.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "key": {"type": "string", "description": "Semantic key, e.g. 'bedtime'."},
                "value": {"type": "string", "description": "Value to store."},
                "category": {
                    "type": "string",
                    "enum": ["preferences", "facts", "habits", "health", "routines"],
                },
            },
            "required": ["key", "value", "category"],
        },
    },
    {
        "name": "query_memory",
        "description": "Search the user's stored memories.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Search string."},
                "category_filter": {
                    "type": "string",
                    "enum": ["preferences", "facts", "habits", "health", "routines", "all"],
                    "default": "all",
                },
            },
            "required": ["query"],
        },
    },
    {
        "name": "analyze_nutrition",
        "description": "Analyze a food label from OCR text and give a health recommendation.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "ocr_text": {"type": "string", "description": "Raw text from food label OCR."},
                "occasion": {"type": "string", "description": "Meal context (breakfast, snack, etc.)."},
                "quantity": {"type": "number", "description": "Number of servings. Defaults to 1."},
                "is_cheat_meal": {"type": "boolean", "default": False},
                "user_health_context": {"type": "string"},
            },
            "required": ["ocr_text"],
        },
    },
    {
        "name": "get_user_context",
        "description": "Retrieve a snapshot of the user's memories, reminders, and upcoming events.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "include_memories": {"type": "boolean", "default": True},
                "include_reminders": {"type": "boolean", "default": True},
                "include_events": {"type": "boolean", "default": True},
            },
        },
    },
]


# ─── Nova Sonic format ────────────────────────────────────────────────────────

def sonic_tool_configuration() -> dict[str, Any]:
    """Format tool definitions for the Nova Sonic toolConfiguration field."""
    return {
        "tools": [
            {
                "toolSpec": {
                    "name": t["name"],
                    "description": t["description"],
                    "inputSchema": {"json": t["inputSchema"]},
                }
            }
            for t in TOOL_DEFINITIONS
        ]
    }


# ─── Claude (Anthropic SDK) format ───────────────────────────────────────────

def claude_tool_definitions() -> list[dict[str, Any]]:
    """Format tool definitions for the Anthropic messages API."""
    return [
        {
            "name": t["name"],
            "description": t["description"],
            "input_schema": t["inputSchema"],
        }
        for t in TOOL_DEFINITIONS
    ]
