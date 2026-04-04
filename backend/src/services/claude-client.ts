import { env } from '../config/env.js';
import { logger } from '../lib/logger.js';
import { claudeToolDefinitions } from '../shared/tool-definitions.js';
import { ToolExecutor } from './tool-executor.js';

type ClaudeTextBlock = {
  type: 'text';
  text: string;
};

type ClaudeToolUseBlock = {
  type: 'tool_use';
  id: string;
  name: string;
  input: Record<string, unknown>;
};

type ClaudeContentBlock = ClaudeTextBlock | ClaudeToolUseBlock | Record<string, unknown>;

type ClaudeResponse = {
  content: ClaudeContentBlock[];
  stop_reason: string | null;
};

type ClaudeMessage = {
  role: 'user' | 'assistant';
  content: ClaudeContentBlock[];
};

export class ClaudeClient {
  constructor(private readonly toolExecutor: ToolExecutor) {}

  async sendTextTurn(params: {
    systemPrompt: string;
    userText: string;
  }): Promise<{ text: string; toolNames: string[] }> {
    if (!env.ANTHROPIC_API_KEY) {
      return {
        text: 'Claude API key is not configured for the text path yet.',
        toolNames: [],
      };
    }

    const messages: ClaudeMessage[] = [
      {
        role: 'user',
        content: [{ type: 'text', text: params.userText }],
      },
    ];
    const toolNames = new Set<string>();

    for (let attempt = 0; attempt < 6; attempt += 1) {
      const response = await this.createMessage({
        systemPrompt: params.systemPrompt,
        messages,
      });

      messages.push({
        role: 'assistant',
        content: response.content,
      });

      const toolCalls = response.content.filter(
        (block): block is ClaudeToolUseBlock =>
          (block as ClaudeToolUseBlock).type === 'tool_use',
      );

      if (toolCalls.length === 0) {
        const text = response.content
          .filter((block): block is ClaudeTextBlock => block.type === 'text')
          .map((block) => block.text)
          .join('')
          .trim();

        return {
          text: text || 'No response returned.',
          toolNames: [...toolNames],
        };
      }

      const toolResults = [];
      for (const toolCall of toolCalls) {
        toolNames.add(toolCall.name);
        const result = await this.toolExecutor.execute(toolCall.name, toolCall.input);
        toolResults.push({
          type: 'tool_result',
          tool_use_id: toolCall.id,
          content: JSON.stringify(result),
        });
      }

      messages.push({
        role: 'user',
        content: toolResults,
      });
    }

    throw new Error('Claude tool loop exceeded the maximum number of turns.');
  }

  private async createMessage(params: {
    systemPrompt: string;
    messages: ClaudeMessage[];
  }): Promise<ClaudeResponse> {
    const response = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
        'x-api-key': env.ANTHROPIC_API_KEY!,
      },
      body: JSON.stringify({
        model: env.ANTHROPIC_MODEL,
        max_tokens: env.ANTHROPIC_MAX_TOKENS,
        system: params.systemPrompt,
        tools: claudeToolDefinitions,
        messages: params.messages,
      }),
    });

    if (!response.ok) {
      const body = await response.text();
      logger.error('Claude request failed', {
        status: response.status,
        body,
      });
      throw new Error(`Claude request failed with status ${response.status}.`);
    }

    return (await response.json()) as ClaudeResponse;
  }
}
