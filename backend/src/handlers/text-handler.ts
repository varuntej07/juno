import { env } from '../config/env.js';
import { logger } from '../lib/logger.js';
import { ClaudeClient } from '../services/claude-client.js';
import { ToolExecutor } from '../services/tool-executor.js';

type ApiEvent = {
  body?: string | null;
  requestContext?: {
    authorizer?: {
      jwt?: {
        claims?: Record<string, string>;
      };
    };
  };
};

type ApiResponse = {
  statusCode: number;
  headers?: Record<string, string>;
  body: string;
};

const json = (statusCode: number, payload: Record<string, unknown>): ApiResponse => ({
  statusCode,
  headers: {
    'content-type': 'application/json',
  },
  body: JSON.stringify(payload),
});

const resolveUserId = (
  event: ApiEvent,
  body: Record<string, unknown>,
): string | null => {
  return (
    event.requestContext?.authorizer?.jwt?.claims?.sub ??
    (typeof body.user_id === 'string' ? body.user_id : null)
  );
};

const buildSystemPrompt = async (toolExecutor: ToolExecutor): Promise<string> => {
  const context = await toolExecutor.execute('get_user_context', {});
  return `${env.JUNO_DEFAULT_SYSTEM_PROMPT}

Ground yourself in this user context before answering:
${JSON.stringify(context, null, 2)}
`;
};

export const handleChatRequest = async (event: ApiEvent): Promise<ApiResponse> => {
  try {
    const body = event.body ? (JSON.parse(event.body) as Record<string, unknown>) : {};
    const userId = resolveUserId(event, body);
    const message = typeof body.message === 'string' ? body.message.trim() : '';

    if (!userId) {
      return json(401, { error: 'Missing authenticated user.' });
    }
    if (!message) {
      return json(400, { error: 'message is required.' });
    }

    const toolExecutor = new ToolExecutor(userId);
    const claude = new ClaudeClient(toolExecutor);
    const response = await claude.sendTextTurn({
      systemPrompt: await buildSystemPrompt(toolExecutor),
      userText: message,
    });

    return json(200, {
      text: response.text,
      intent: 'assistant_response',
      metadata: {
        tool_names: response.toolNames,
      },
    });
  } catch (error) {
    logger.error('handleChatRequest failed', {
      error: error instanceof Error ? error.message : String(error),
    });
    return json(500, {
      error: 'Failed to process chat request.',
    });
  }
};

export const handleNutritionAnalyzeRequest = async (
  event: ApiEvent,
): Promise<ApiResponse> => {
  try {
    const body = event.body ? (JSON.parse(event.body) as Record<string, unknown>) : {};
    const userId = resolveUserId(event, body);
    if (!userId) {
      return json(401, { error: 'Missing authenticated user.' });
    }
    if (typeof body.ocr_text !== 'string' || body.ocr_text.trim().length === 0) {
      return json(400, { error: 'ocr_text is required.' });
    }

    const toolExecutor = new ToolExecutor(userId);
    const result = await toolExecutor.execute('analyze_nutrition', body);
    return json(200, result);
  } catch (error) {
    logger.error('handleNutritionAnalyzeRequest failed', {
      error: error instanceof Error ? error.message : String(error),
    });
    return json(500, {
      error: 'Failed to analyze nutrition.',
    });
  }
};
