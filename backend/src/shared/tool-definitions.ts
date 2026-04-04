export interface SharedToolDefinition {
  readonly name: string;
  readonly description: string;
  readonly inputSchema: Record<string, unknown>;
}

export const sharedToolDefinitions: readonly SharedToolDefinition[] = [
  {
    name: 'set_reminder',
    description:
      'Set a time-delayed reminder. The system will notify the user after the specified delay.',
    inputSchema: {
      type: 'object',
      properties: {
        message: { type: 'string', description: 'What to remind the user about' },
        delay_minutes: {
          type: 'integer',
          description: 'Minutes from now to trigger',
        },
        priority: {
          type: 'string',
          enum: ['low', 'normal', 'urgent'],
          default: 'normal',
        },
      },
      required: ['message', 'delay_minutes'],
    },
  },
  {
    name: 'list_reminders',
    description: 'List all pending reminders for the user',
    inputSchema: {
      type: 'object',
      properties: {
        status_filter: {
          type: 'string',
          enum: ['pending', 'fired', 'all'],
          default: 'pending',
        },
      },
    },
  },
  {
    name: 'cancel_reminder',
    description: 'Cancel a pending reminder by its ID',
    inputSchema: {
      type: 'object',
      properties: {
        reminder_id: { type: 'string' },
      },
      required: ['reminder_id'],
    },
  },
  {
    name: 'create_calendar_event',
    description: 'Create a new Google Calendar event',
    inputSchema: {
      type: 'object',
      properties: {
        title: { type: 'string' },
        start_time: { type: 'string', description: 'ISO 8601 datetime' },
        end_time: { type: 'string', description: 'ISO 8601 datetime' },
        description: { type: 'string' },
        location: { type: 'string' },
      },
      required: ['title', 'start_time'],
    },
  },
  {
    name: 'get_upcoming_events',
    description: 'Retrieve upcoming calendar events within a time window',
    inputSchema: {
      type: 'object',
      properties: {
        hours_ahead: { type: 'integer', default: 24 },
        calendar_source: {
          type: 'string',
          enum: ['google', 'apple', 'all'],
          default: 'all',
        },
      },
    },
  },
  {
    name: 'store_memory',
    description:
      'Persist a fact, preference, or context about the user for future retrieval',
    inputSchema: {
      type: 'object',
      properties: {
        key: {
          type: 'string',
          description: "Semantic key like 'diet_goal' or 'favorite_grocery_store'",
        },
        value: {
          type: 'string',
          description: 'The information to store',
        },
        category: {
          type: 'string',
          enum: ['preferences', 'facts', 'habits', 'health', 'routines'],
        },
      },
      required: ['key', 'value', 'category'],
    },
  },
  {
    name: 'query_memory',
    description: 'Search stored memories for context relevant to the current conversation',
    inputSchema: {
      type: 'object',
      properties: {
        query: {
          type: 'string',
          description: 'Natural language query to search memories',
        },
        category_filter: {
          type: 'string',
          enum: ['preferences', 'facts', 'habits', 'health', 'routines', 'all'],
          default: 'all',
        },
      },
      required: ['query'],
    },
  },
  {
    name: 'analyze_nutrition',
    description:
      'Analyze nutritional information from OCR-scanned food label text. Ask contextual follow-up questions about occasion, quantity, and whether this is a cheat meal before giving final assessment.',
    inputSchema: {
      type: 'object',
      properties: {
        ocr_text: {
          type: 'string',
          description: 'Raw OCR text from nutritional label',
        },
        occasion: {
          type: 'string',
          description:
            'Meal occasion: breakfast, lunch, dinner, snack, pre-workout, post-workout',
        },
        quantity: {
          type: 'integer',
          description: 'Number of servings the user intends to consume',
        },
        is_cheat_meal: {
          type: 'boolean',
          description: 'Whether user considers this a cheat meal',
        },
        user_health_context: {
          type: 'string',
          description: 'Relevant health memories retrieved from query_memory',
        },
      },
      required: ['ocr_text'],
    },
  },
  {
    name: 'get_user_context',
    description:
      "Retrieve the user's current context: recent memories, pending reminders, and upcoming events. Use this at the start of every session to ground responses.",
    inputSchema: {
      type: 'object',
      properties: {
        include_memories: { type: 'boolean', default: true },
        include_reminders: { type: 'boolean', default: true },
        include_events: { type: 'boolean', default: true },
      },
    },
  },
] as const;

export const sonicToolConfiguration = {
  tools: sharedToolDefinitions.map((tool) => ({
    toolSpec: {
      name: tool.name,
      description: tool.description,
      inputSchema: {
        json: tool.inputSchema,
      },
    },
  })),
  toolChoice: {
    auto: {},
  },
} as const;

export const claudeToolDefinitions = sharedToolDefinitions.map((tool) => ({
  name: tool.name,
  description: tool.description,
  input_schema: tool.inputSchema,
}));
