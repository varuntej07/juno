import { randomUUID } from 'node:crypto';

import {
  BedrockRuntimeClient,
  InvokeModelWithBidirectionalStreamCommand,
} from '@aws-sdk/client-bedrock-runtime';
import { NodeHttp2Handler } from '@smithy/node-http-handler';

import { env } from '../config/env.js';
import { AsyncJsonQueue } from '../lib/async-json-queue.js';
import { logger } from '../lib/logger.js';
import { sonicToolConfiguration } from '../shared/tool-definitions.js';
import { VoiceServerMessage } from '../shared/voice-protocol.js';
import { ToolExecutor, logToolFailure } from './tool-executor.js';

const decoder = new TextDecoder();

export class SonicRealtimeSession {
  private readonly sessionId = randomUUID();
  private readonly promptName = `prompt-${this.sessionId}`;
  private readonly audioContentName = `audio-${this.sessionId}`;
  private readonly inputQueue = new AsyncJsonQueue();
  private readonly bedrock = new BedrockRuntimeClient({
    region: env.AWS_REGION,
    requestHandler: new NodeHttp2Handler({
      requestTimeout: 300_000,
      sessionTimeout: 300_000,
      disableConcurrentStreams: false,
    }),
  });

  private readonly accumulatedAssistantText: string[] = [];
  private endedInput = false;
  private started = false;
  private outputSampleRate = env.VOICE_GATEWAY_SAMPLE_RATE_HZ;
  private processingResponse?: Promise<void>;

  constructor(
    private readonly params: {
      userId: string;
      voiceId?: string;
      systemPrompt?: string;
      send: (message: VoiceServerMessage) => void;
    },
    private readonly toolExecutor: ToolExecutor,
  ) {}

  async start(): Promise<void> {
    if (this.started) {
      return;
    }
    this.started = true;

    const response = (await this.bedrock.send(
      new InvokeModelWithBidirectionalStreamCommand({
        modelId: env.BEDROCK_SONIC_MODEL_ID,
        body: this.inputQueue,
      }),
    )) as { body?: AsyncIterable<Record<string, unknown>> };

    if (!response.body) {
      throw new Error('Nova Sonic stream did not return a response body.');
    }

    this.enqueueStartEvents();
    this.params.send({
      type: 'session.ready',
      sessionId: this.sessionId,
    });
    this.params.send({
      type: 'session.state',
      sessionId: this.sessionId,
      payload: { state: 'listening' },
    });

    this.processingResponse = this.processResponseStream(response.body);
  }

  get id(): string {
    return this.sessionId;
  }

  sendAudioChunk(audioBase64: string): void {
    this.inputQueue.enqueue({
      event: {
        audioInput: {
          promptName: this.promptName,
          contentName: this.audioContentName,
          content: audioBase64,
        },
      },
    });
  }

  sendTextInput(text: string): void {
    const contentName = `text-${randomUUID()}`;
    this.inputQueue.enqueue({
      event: {
        contentStart: {
          promptName: this.promptName,
          contentName,
          type: 'TEXT',
          textInputConfiguration: {
            mediaType: 'text/plain',
          },
          interactive: true,
          role: 'USER',
        },
      },
    });
    this.inputQueue.enqueue({
      event: {
        textInput: {
          promptName: this.promptName,
          contentName,
          content: text,
        },
      },
    });
    this.inputQueue.enqueue({
      event: {
        contentEnd: {
          promptName: this.promptName,
          contentName,
        },
      },
    });
  }

  sendOcrContext(text: string): void {
    const contentName = `ocr-${randomUUID()}`;
    this.inputQueue.enqueue({
      event: {
        contentStart: {
          promptName: this.promptName,
          contentName,
          type: 'TEXT',
          textInputConfiguration: {
            mediaType: 'text/plain',
          },
          interactive: false,
          role: 'SYSTEM',
        },
      },
    });
    this.inputQueue.enqueue({
      event: {
        textInput: {
          promptName: this.promptName,
          contentName,
          content: `OCR context from the user camera scan:\n${text}`,
        },
      },
    });
    this.inputQueue.enqueue({
      event: {
        contentEnd: {
          promptName: this.promptName,
          contentName,
        },
      },
    });
  }

  endInput(): void {
    if (this.endedInput) {
      return;
    }
    this.endedInput = true;
    this.params.send({
      type: 'session.state',
      sessionId: this.sessionId,
      payload: { state: 'processing' },
    });
    this.inputQueue.enqueue({
      event: {
        contentEnd: {
          promptName: this.promptName,
          contentName: this.audioContentName,
        },
      },
    });
    this.inputQueue.enqueue({
      event: {
        promptEnd: {
          promptName: this.promptName,
        },
      },
    });
    this.inputQueue.enqueue({
      event: {
        sessionEnd: {},
      },
    });
    this.inputQueue.close();
  }

  async cancel(): Promise<void> {
    this.inputQueue.close();
    await this.processingResponse?.catch(() => undefined);
  }

  private enqueueStartEvents(): void {
    const systemContentName = `system-${randomUUID()}`;

    this.inputQueue.enqueue({
      event: {
        sessionStart: {
          inferenceConfiguration: {
            maxTokens: env.VOICE_GATEWAY_INPUT_MAX_TOKENS,
            topP: env.VOICE_GATEWAY_TOP_P,
            temperature: env.VOICE_GATEWAY_TEMPERATURE,
          },
          turnDetectionConfiguration: {
            endpointingSensitivity: 'MEDIUM',
          },
        },
      },
    });

    this.inputQueue.enqueue({
      event: {
        promptStart: {
          promptName: this.promptName,
          textOutputConfiguration: {
            mediaType: 'text/plain',
          },
          audioOutputConfiguration: {
            mediaType: 'audio/lpcm',
            sampleRateHertz: env.VOICE_GATEWAY_SAMPLE_RATE_HZ,
            sampleSizeBits: 16,
            channelCount: 1,
            voiceId: this.params.voiceId ?? env.BEDROCK_SONIC_VOICE,
            encoding: 'base64',
            audioType: 'SPEECH',
          },
          toolUseOutputConfiguration: {
            mediaType: 'application/json',
          },
          toolConfiguration: sonicToolConfiguration,
        },
      },
    });

    this.inputQueue.enqueue({
      event: {
        contentStart: {
          promptName: this.promptName,
          contentName: systemContentName,
          type: 'TEXT',
          textInputConfiguration: {
            mediaType: 'text/plain',
          },
          interactive: false,
          role: 'SYSTEM',
        },
      },
    });

    this.inputQueue.enqueue({
      event: {
        textInput: {
          promptName: this.promptName,
          contentName: systemContentName,
          content:
            this.params.systemPrompt ?? env.JUNO_DEFAULT_SYSTEM_PROMPT,
        },
      },
    });

    this.inputQueue.enqueue({
      event: {
        contentEnd: {
          promptName: this.promptName,
          contentName: systemContentName,
        },
      },
    });

    this.inputQueue.enqueue({
      event: {
        contentStart: {
          promptName: this.promptName,
          contentName: this.audioContentName,
          type: 'AUDIO',
          audioInputConfiguration: {
            mediaType: 'audio/lpcm',
            sampleRateHertz: env.VOICE_GATEWAY_SAMPLE_RATE_HZ,
            sampleSizeBits: 16,
            channelCount: 1,
            audioType: 'SPEECH',
            encoding: 'base64',
          },
          interactive: true,
          role: 'USER',
        },
      },
    });
  }

  private async processResponseStream(
    body: AsyncIterable<Record<string, unknown>>,
  ): Promise<void> {
    try {
      for await (const streamEvent of body) {
        this.throwIfStreamError(streamEvent);
        const chunk = (streamEvent as { chunk?: { bytes?: Uint8Array } }).chunk?.bytes;
        if (!chunk || chunk.length === 0) {
          continue;
        }

        const payload = JSON.parse(decoder.decode(chunk)) as {
          event?: Record<string, unknown>;
        };
        const event = payload.event ?? {};

        const textOutput = event.textOutput as
          | { content?: string; role?: string }
          | undefined;
        if (textOutput?.content && textOutput.role !== 'USER') {
          this.accumulatedAssistantText.push(textOutput.content);
          this.params.send({
            type: 'assistant.text.delta',
            sessionId: this.sessionId,
            text: textOutput.content,
          });
          this.params.send({
            type: 'session.state',
            sessionId: this.sessionId,
            payload: { state: 'speaking' },
          });
        }

        const streamedSampleRate =
          ((event.contentStart as { audioOutputConfiguration?: { sampleRateHertz?: number } })
            ?.audioOutputConfiguration?.sampleRateHertz ??
            undefined);
        if (typeof streamedSampleRate === 'number' && streamedSampleRate > 0) {
          this.outputSampleRate = streamedSampleRate;
        }

        const audioOutput = event.audioOutput as { content?: string } | undefined;
        if (audioOutput?.content) {
          this.params.send({
            type: 'assistant.audio.chunk',
            sessionId: this.sessionId,
            audioBase64: audioOutput.content,
            mimeType: 'audio/lpcm',
            sampleRateHertz: this.outputSampleRate,
          });
        }

        const toolUse = event.toolUse as
          | {
              toolName?: string;
              content?: string;
              contentId?: string;
            }
          | undefined;
        if (toolUse?.toolName && toolUse.contentId) {
          await this.handleToolUse(toolUse);
        }

        if (event.completionEnd) {
          break;
        }
      }
    } catch (error) {
      logger.error('Nova Sonic session failed', {
        sessionId: this.sessionId,
        error: error instanceof Error ? error.message : String(error),
      });
      this.params.send({
        type: 'error',
        sessionId: this.sessionId,
        message:
          error instanceof Error ? error.message : 'Nova Sonic session failed.',
      });
    } finally {
      const finalText = this.accumulatedAssistantText.join('').trim();
      if (finalText) {
        this.params.send({
          type: 'assistant.text.final',
          sessionId: this.sessionId,
          text: finalText,
        });
      }
      this.params.send({
        type: 'session.ended',
        sessionId: this.sessionId,
      });
    }
  }

  private async handleToolUse(toolUse: {
    toolName?: string;
    content?: string;
    contentId?: string;
  }): Promise<void> {
    const toolName = toolUse.toolName!;
    const parsedInput = toolUse.content ? JSON.parse(toolUse.content) : {};
    this.params.send({
      type: 'tool.call',
      sessionId: this.sessionId,
      toolName,
      payload: parsedInput,
    });

    try {
      const result = await this.toolExecutor.execute(toolName, parsedInput);
      this.inputQueue.enqueue({
        event: {
          toolResult: {
            promptName: this.promptName,
            contentName: toolUse.contentId,
            content: JSON.stringify(result),
          },
        },
      });
      this.params.send({
        type: 'tool.result',
        sessionId: this.sessionId,
        toolName,
        payload: result,
      });
    } catch (error) {
      logToolFailure(toolName, error);
      const result = {
        error: error instanceof Error ? error.message : 'Tool execution failed.',
      };
      this.inputQueue.enqueue({
        event: {
          toolResult: {
            promptName: this.promptName,
            contentName: toolUse.contentId,
            content: JSON.stringify(result),
          },
        },
      });
      this.params.send({
        type: 'tool.result',
        sessionId: this.sessionId,
        toolName,
        payload: result,
      });
    }
  }

  private throwIfStreamError(streamEvent: Record<string, unknown>): void {
    const errorKeys = [
      'validationException',
      'modelStreamErrorException',
      'internalServerException',
      'throttlingException',
      'serviceUnavailableException',
      'modelTimeoutException',
    ] as const;

    for (const key of errorKeys) {
      const maybeError = streamEvent[key] as { message?: string } | undefined;
      if (maybeError) {
        throw new Error(maybeError.message ?? `Nova Sonic stream returned ${key}.`);
      }
    }
  }
}
