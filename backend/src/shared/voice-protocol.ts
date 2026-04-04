import { z } from 'zod';

export const voiceSessionConfigSchema = z.object({
  userId: z.string().min(1),
  locale: z.string().optional(),
  voiceId: z.string().optional(),
  systemPrompt: z.string().optional(),
});

export const voiceClientMessageSchema = z.discriminatedUnion('type', [
  z.object({
    type: z.literal('session.start'),
    payload: voiceSessionConfigSchema,
  }),
  z.object({
    type: z.literal('input.audio'),
    payload: z.object({
      audioBase64: z.string().min(1),
    }),
  }),
  z.object({
    type: z.literal('input.text'),
    payload: z.object({
      text: z.string().min(1),
    }),
  }),
  z.object({
    type: z.literal('input.ocr_context'),
    payload: z.object({
      text: z.string().min(1),
    }),
  }),
  z.object({
    type: z.literal('input.end'),
  }),
  z.object({
    type: z.literal('session.cancel'),
  }),
  z.object({
    type: z.literal('ping'),
  }),
]);

export type VoiceClientMessage = z.infer<typeof voiceClientMessageSchema>;

export type VoiceServerMessage =
  | {
      type: 'session.ready';
      sessionId: string;
    }
  | {
      type: 'session.state';
      sessionId: string;
      payload: { state: 'listening' | 'processing' | 'speaking' };
    }
  | {
      type: 'assistant.text.delta';
      sessionId: string;
      text: string;
    }
  | {
      type: 'assistant.text.final';
      sessionId: string;
      text: string;
    }
  | {
      type: 'assistant.audio.chunk';
      sessionId: string;
      audioBase64: string;
      mimeType: string;
      sampleRateHertz?: number;
    }
  | {
      type: 'tool.call';
      sessionId: string;
      toolName: string;
      payload: Record<string, unknown>;
    }
  | {
      type: 'tool.result';
      sessionId: string;
      toolName: string;
      payload: Record<string, unknown>;
    }
  | {
      type: 'pong';
      sessionId: string;
    }
  | {
      type: 'error';
      sessionId?: string;
      message: string;
    }
  | {
      type: 'session.ended';
      sessionId?: string;
    };
