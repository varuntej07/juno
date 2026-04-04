# Juno Backend

This backend is split across two execution models:

- `src/voice-gateway/`: a stateful WebSocket worker that owns the realtime Nova Sonic session. This is the only safe place to proxy full-duplex audio and tool use.
- `src/handlers/`: stateless Lambda-friendly HTTP/background handlers for text chat, notification replies, and scheduled reminder delivery.

Why not Lambda-only for voice:

- API Gateway WebSocket + Lambda is fine for discrete messages.
- Nova Sonic speech sessions require a long-lived bidirectional stream with shared in-memory state across incoming audio frames, tool calls, and outgoing audio/text deltas.
- A dedicated voice gateway matches that requirement cleanly. It also mirrors the transport pattern used in working Nova Sonic samples.

## Structure

- `src/shared/`: transport contracts and shared tool definitions
- `src/services/`: Bedrock, Claude, Firestore, Calendar, FCM, and tool execution
- `src/voice-gateway/`: websocket server and realtime session orchestration
- `src/handlers/`: REST and scheduled entrypoints

## Run locally

```bash
npm install
npm run dev:voice
```

The Flutter app should point `wsBaseUrl` at the voice gateway and `apiBaseUrl` at your REST deployment.
