import { createServer } from 'node:http';

import { WebSocket, WebSocketServer } from 'ws';

import { env } from '../config/env.js';
import { logger } from '../lib/logger.js';
import {
  VoiceServerMessage,
  voiceClientMessageSchema,
} from '../shared/voice-protocol.js';
import { adminAuth } from '../services/firebase-admin.js';
import { SonicRealtimeSession } from '../services/sonic-realtime-session.js';
import { ToolExecutor } from '../services/tool-executor.js';

type ConnectionContext = {
  userId: string;
  session?: SonicRealtimeSession;
};

const send = (ws: WebSocket, message: VoiceServerMessage): void => {
  if (ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(message));
  }
};

const resolveUserId = async (ws: WebSocket, authorization?: string, fallbackUserId?: string) => {
  if (authorization?.startsWith('Bearer ')) {
    const token = authorization.slice('Bearer '.length).trim();
    const decoded = await adminAuth().verifyIdToken(token);
    return decoded.uid;
  }

  if (fallbackUserId && process.env.NODE_ENV !== 'production') {
    return fallbackUserId;
  }

  send(ws, {
    type: 'error',
    message: 'Missing valid bearer token for the voice gateway connection.',
  });
  ws.close(1008, 'Unauthorized');
  throw new Error('Unauthorized websocket connection.');
};

const server = createServer((request, response) => {
  if (request.url === '/health') {
    response.writeHead(200, { 'content-type': 'application/json' });
    response.end(JSON.stringify({ ok: true }));
    return;
  }

  response.writeHead(404, { 'content-type': 'application/json' });
  response.end(JSON.stringify({ error: 'Not found' }));
});

const wss = new WebSocketServer({ noServer: true });

server.on('upgrade', (request, socket, head) => {
  const url = new URL(request.url ?? '/', `http://${request.headers.host ?? 'localhost'}`);
  if (url.pathname !== '/voice/stream') {
    socket.destroy();
    return;
  }

  wss.handleUpgrade(request, socket, head, (ws) => {
    wss.emit('connection', ws, request);
  });
});

wss.on('connection', async (ws, request) => {
  const context: ConnectionContext = {
    userId: '',
  };

  try {
    context.userId = await resolveUserId(
      ws,
      request.headers.authorization,
      typeof request.headers['x-juno-user-id'] === 'string'
        ? request.headers['x-juno-user-id']
        : undefined,
    );
  } catch (error) {
    logger.error('Voice gateway authentication failed', {
      error: error instanceof Error ? error.message : String(error),
    });
    return;
  }

  logger.info('Voice gateway client connected', { userId: context.userId });

  ws.on('message', async (data) => {
    try {
      const raw = typeof data === 'string' ? data : data.toString('utf-8');
      const parsed = voiceClientMessageSchema.parse(JSON.parse(raw));

      switch (parsed.type) {
        case 'session.start': {
          if (context.session) {
            send(ws, {
              type: 'error',
              sessionId: context.session.id,
              message: 'A voice session is already active on this connection.',
            });
            return;
          }

          if (parsed.payload.userId !== context.userId) {
            send(ws, {
              type: 'error',
              message: 'Session user mismatch.',
            });
            return;
          }

          const session = new SonicRealtimeSession(
            {
              userId: context.userId,
              voiceId: parsed.payload.voiceId,
              systemPrompt: parsed.payload.systemPrompt,
              send: (message) => send(ws, message),
            },
            new ToolExecutor(context.userId),
          );
          context.session = session;
          await session.start();
          break;
        }
        case 'input.audio':
          context.session?.sendAudioChunk(parsed.payload.audioBase64);
          break;
        case 'input.text':
          context.session?.sendTextInput(parsed.payload.text);
          break;
        case 'input.ocr_context':
          context.session?.sendOcrContext(parsed.payload.text);
          break;
        case 'input.end':
          context.session?.endInput();
          break;
        case 'session.cancel':
          await context.session?.cancel();
          context.session = undefined;
          send(ws, {
            type: 'session.ended',
          });
          break;
        case 'ping':
          send(ws, {
            type: 'pong',
            sessionId: context.session?.id ?? 'unbound',
          });
          break;
      }
    } catch (error) {
      logger.error('Voice gateway message handling failed', {
        userId: context.userId,
        error: error instanceof Error ? error.message : String(error),
      });
      send(ws, {
        type: 'error',
        sessionId: context.session?.id,
        message:
          error instanceof Error ? error.message : 'Invalid realtime message.',
      });
    }
  });

  ws.on('close', () => {
    logger.info('Voice gateway client disconnected', { userId: context.userId });
    void context.session?.cancel();
  });

  ws.on('error', (error) => {
    logger.error('Voice gateway websocket error', {
      userId: context.userId,
      error: error.message,
    });
  });
});

server.listen(env.VOICE_GATEWAY_PORT, env.VOICE_GATEWAY_HOST, () => {
  logger.info('Voice gateway listening', {
    host: env.VOICE_GATEWAY_HOST,
    port: env.VOICE_GATEWAY_PORT,
  });
});
