# Juno Backend

FastAPI backend for the Juno/Buddy mobile app, deployed on Google Cloud Run.

## Runtime Model

- `src/main.py`: FastAPI HTTP API served by `uvicorn` on Cloud Run.
- `src/agent/voice_agent.py`: LiveKit voice worker, run as a separate long-lived process.
- `src/handlers/`: REST and scheduled endpoint logic for chat, nutrition, reminders, devices, connectors, engagement, and daily notifications.
- `src/services/`: integrations for Claude, Gemini/Vertex AI, Firebase, Google Calendar, FCM, Cloud Tasks, and tool execution.

Voice is handled through LiveKit:

- Deepgram for speech-to-text.
- Claude for assistant reasoning.
- Cartesia for text-to-speech.
- Silero VAD through LiveKit Agents.

## Run Locally

Run the HTTP API:

```bash
cd backend
uvicorn src.main:app --reload --port 8000
```

Run the voice worker in a second terminal:

```bash
cd backend
python -m src.agent.voice_agent start
```

The Flutter app should point `apiBaseUrl` at the FastAPI service and use LiveKit for voice sessions.

## Deploy

From the repository root:

```bash
gcloud run deploy juno-backend --source backend/ --region us-central1 --project juno-2ea45
```

Cloud Run environment variables and secrets are persisted. Only pass `--set-env-vars` or `--set-secrets` when changing configuration.
