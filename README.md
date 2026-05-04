# Aura

Aura is my personal Flutter and FastAPI assistant app for chat, voice, reminders, nutrition, notifications, and calendar tools.

It is useful as a personal project, but reliability still depends on external services and clean local configuration. Keep Firebase, Anthropic, Gemini, LiveKit, Deepgram, Cartesia, Google Calendar, Cloud Scheduler, Cloud Tasks, and FCM failures visible instead of hiding them.

Keep changes small. Prefer boring fixes, clear configuration, and one working path over broad rewrites.

## Run

Backend:

```powershell
cd backend
uvicorn src.main:app --reload --port 8000
```

App:

```powershell
flutter run
```