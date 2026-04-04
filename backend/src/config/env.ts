import { z } from 'zod';

const envSchema = z.object({
  AWS_REGION: z.string().default('us-east-1'),
  BEDROCK_SONIC_MODEL_ID: z.string().default('us.amazon.nova-2-sonic-v1:0'),
  BEDROCK_SONIC_VOICE: z.string().default('matthew'),
  VOICE_GATEWAY_PORT: z.coerce.number().int().positive().default(8787),
  VOICE_GATEWAY_HOST: z.string().default('0.0.0.0'),
  VOICE_GATEWAY_SAMPLE_RATE_HZ: z.coerce.number().int().positive().default(16000),
  VOICE_GATEWAY_INPUT_MAX_TOKENS: z.coerce.number().int().positive().default(1024),
  VOICE_GATEWAY_TEMPERATURE: z.coerce.number().min(0).max(1).default(0.7),
  VOICE_GATEWAY_TOP_P: z.coerce.number().min(0).max(1).default(0.9),
  ANTHROPIC_API_KEY: z.string().optional(),
  ANTHROPIC_MODEL: z.string().default('claude-sonnet-4-5'),
  ANTHROPIC_MAX_TOKENS: z.coerce.number().int().positive().default(1024),
  GOOGLE_CLIENT_ID: z.string().optional(),
  GOOGLE_CLIENT_SECRET: z.string().optional(),
  GOOGLE_REDIRECT_URI: z.string().optional(),
  JUNO_DEFAULT_SYSTEM_PROMPT: z
    .string()
    .default(
      'You are Juno, a proactive personal assistant that helps with reminders, scheduling, memory, and nutrition.',
    ),
});

export const env = envSchema.parse(process.env);
