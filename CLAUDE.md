## Project Overview

**Buddy** is a AI assistant mobile app (Flutter + Python/FastAPI backend). Users interact via voice or text; the assistant manages reminders, memory, nutrition tracking, and calendar events using tool-calling AI (Claude + AWS Nova Sonic).

---

## Architecture

### Frontend (Flutter/Dart) — MVVM + Provider

Layer hierarchy: `core/` → `data/` → `presentation/` → `di/`

- **Screens** (`presentation/screens/`) — UI only. Read state via `Consumer<>` or `context.watch<>()`; never contain business logic.
- **ViewModels** (`presentation/viewmodels/`) — business logic via `ChangeNotifier`. Use `SafeChangeNotifier` (from `core/base/safe_change_notifier.dart`) for all ViewModels.
- **Repositories** (`data/repositories/`) — return `Result<T>` (never throw). Use the `Result<T>` sealed class from `core/network/api_response.dart`.
- **Services** (`data/services/`) — singletons wrapping Firebase, HTTP, WebSocket, and audio APIs.
- **Models** (`data/models/`) — immutable Dart data classes with `fromMap`, `toMap`, `copyWith`, `==`, `hashCode`. No business logic.
- **Widgets** (`presentation/widgets/`) — reusable UI components, no direct service/VM dependencies.

**Provider wiring:** All providers in `di/providers.dart`. ViewModels via `ChangeNotifierProvider` at route level (except long-lived VMs like `AuthViewModel`, `NutritionScanViewModel`, `DietaryProfileViewModel`). Never instantiate a ViewModel inside `build`.

**Navigation:** `AppShell` (`presentation/screens/app_shell.dart`) is the root authenticated widget — 2-tab `BottomNavigationBar` (Home=chat, Agents). `app.dart` routes authenticated users to `AppShell`. `AgentsScreen` hosts all agent cards (Nutrition Agent + Google Calendar). `ConnectorsScreen` is superseded but kept.

**ViewState pattern:** `_setState(loading)` → try/catch → `result.when(success/failure)` → `_setState(loaded/error)`. `ViewState` enum in `presentation/viewmodels/view_state.dart`.

**Auth:** `AuthViewModel` is the single source of truth. Never use `FirebaseAuth.instance.currentUser` directly — always use `context.read<AuthViewModel>().userProfile?.uid`.

**Error handling:** All errors go to `core/errors/error_handler.dart`. Services never throw — return `null`/`false`/`Result.failure`. Log via `FirebaseCrashlytics.instance.recordError(...)`.

**HTTP:** Every call must `.timeout(const Duration(seconds: 10))`. Use `response.isSuccess` (from `core/network/`) for 2xx checks.

---

### Backend (Python/FastAPI) — Deployed on GCP Cloud Run

**Production URL:** `https://juno-backend-620715294422.us-central1.run.app`
**Project:** `juno-2ea45` (GCP) | **Region:** `us-central1` | **Min instances:** 1

**Deploy (from repo root, PowerShell):**
```powershell
gcloud run deploy juno-backend --source backend/ --region us-central1 --project juno-2ea45
```
Env vars and secrets are persisted in Cloud Run — only pass `--set-env-vars` / `--set-secrets` when changing them.
**Run locally:** `cd backend && uvicorn src.main:app --reload --port 8000`

**REST handlers** (`src/handlers/`): `chat.py`, `nutrition.py`, `notification_reply.py`, `scheduler.py`, `connectors.py`, `devices.py`, `engagement.py`, `daily_notification.py`

**Voice Gateway** (`src/voice_gateway/ws_handler.py`) — WebSocket at `/voice/stream`. Nova Sonic bidirectional stream. Requires persistent server (Cloud Run min-instances=1).

**Daily notification planning** (`src/services/daily_notification/`): `orchestrator.py` (full pipeline), `planner_agent.py` (`NotificationPlannerAgent` — reads last 10 queries + dietary profile + news, generates `DailyPlan`), `verifier_agent.py` (`PushNotificationAgent` — hard rule checks + single LLM quality gate), `rss_client.py` (Google News RSS with 3-level fallback), `models.py` (`NudgePlan`, `DailyPlan`, `VerificationResult`). Triggered by Cloud Scheduler at 6 AM UTC → fan-out Cloud Tasks → one plan per user per day. Always produces 2 notifications (morning + evening); 1 planner retry on rejection, then `safe_default`. Endpoints: `POST /internal/daily-notify/plan-all|plan/{uid}|send` (OIDC-gated).

**Key services:**
- `src/services/sonic_session.py` — Nova Sonic via asyncio↔threading bridge + boto3
- `src/services/tool_executor.py` — 9 tools: Firestore CRUD + Google Calendar
- `src/services/claude_client.py` — Anthropic SDK, multi-turn tool loop (max 6 turns), exponential backoff retry (3 attempts) for 529/429/500/connection errors
- **Every new LLM call must have:** SDK-level timeout (`timeout=` on client or `asyncio.wait_for`), retry loop with exponential backoff + jitter matching the pattern in `claude_client.py`, and error logging with `model`, `attempt`, `error_type`, `error`. Use `model_provider.py` as the reference implementation.
- `src/services/firebase.py` — lazy singleton: `admin_auth()`, `admin_firestore()`, `admin_messaging()`
- `src/services/google_calendar_connector.py` — OAuth, token refresh, event sync, webhook
- `src/services/notification_service.py` — `await send_notification(user_id, *, title, body, data, notification_type, priority, collapse_key, ...)` → FCM multicast with auto token cleanup
- `src/services/fcm_token_registry.py` — `register_token`, `get_user_tokens`, `remove_invalid_tokens` (Firestore subcollection `users/{uid}/fcm_tokens/{token}`)

**Tools (`src/shared/tools.py`):** `set_reminder`, `list_reminders`, `cancel_reminder`, `create_calendar_event`, `get_upcoming_events`, `store_memory`, `query_memory`, `analyze_nutrition`, `get_user_context`

**Nutrition VLM** (`src/services/gemini_client.py`) — Vertex AI Gemini 2.0 Flash (ADC, no API key). Two stages: `scan_image()` → confidence + dynamic questions; `analyze_food()` → macros + verdict. Confidence threshold: `NUTRITION_SCAN_CONFIDENCE_THRESHOLD=0.85` (env). In-memory scan cache `_scan_cache` keyed by `scan_id` (adequate for min-instances=1; move to Redis for multi-instance).

**Query logger** (`src/lib/query_logger.py`) — `await log_query(user_id, type, text)`. Call from every handler that receives user input. Types: `"chat"`, `"voice"`, `"nutrition_scan"`. Never raises.

**Secrets** (GCP Secret Manager, project `juno-2ea45`): `juno-anthropic-api-key`, `juno-aws-access-key-id`, `juno-aws-secret-access-key`, `juno-google-client-id`, `juno-google-client-secret`, `juno-firebase-service-account`, `juno-gemini-api-key`

**GCP one-time setup for Vertex AI:**
```
gcloud services enable aiplatform.googleapis.com --project juno-2ea45
gcloud projects add-iam-policy-binding juno-2ea45 --member="serviceAccount:<SA_EMAIL>" --role="roles/aiplatform.user"
```

---

## Environments

| Env  | API URL                                                 | Flutter flag                         |
|------|---------------------------------------------------------|--------------------------------------|
| dev  | `http://<LAN-IP>:8000` (see `dev_targets.dart`)         | `flutter run`                        |
| prod | `https://juno-backend-620715294422.us-central1.run.app` | `flutter run --dart-define=ENV=prod` |

**Google OAuth client** (all envs): `620715294422-15h8gdqn7ii0b419ksfrf8u7fgghltoi.apps.googleusercontent.com`
**Wireless Debugging:** `%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe connect <IP>:<PORT>` (Run when phone disconnects to re-establish Wi-Fi debugging)

---

## Firestore Schema

```
users/{uid}                          — profile + settings (wake_word_enabled, tts_enabled, default_reminder_lead_minutes, timezone [IANA string, detected from device on every sign-in])
users/{uid}/reminders/{id}           — message, trigger_at, status, priority, snooze_count, created_via
users/{uid}/memories/{id}            — key, value, category, source, created_at, updated_at
users/{uid}/fcm_tokens/{token}       — token, platform ("android"|"ios"|"web"), registered_at
users/{uid}/dietary_profile/data     — age, gender, height_cm, weight_kg, goal, activity_level, workout_min_per_day, restrictions[], allergies[], fat_pct
users/{uid}/nutrition_logs/{id}      — scan_id, detected_items[], confidence, questions_asked[], user_answers{}, food_name, macros{}, recommendation, verdict_reason, concerns[], created_at
users/{uid}/queries/{id}             — text, type ("chat"|"voice"|"nutrition_scan"), timestamp, session_id?
users/{uid}/feedback/{messageId}     — message_id, session_id, feedback ("liked"|"disliked"), message_content (truncated), created_at, updated_at
users/{uid}/engagement_log/{id}      — trigger_event, chosen_agent, notification_title/body, initial_chat_message, suggested_replies, status, actions_completed[], cloud_task_name, re_engagement_count
users/{uid}/engagement_guard/state   — last_engaged_at, last_app_interaction_at, guard_date, proactive_notifications_sent_today, user_action_notifications_sent_today
users/{uid}/engagement_analytics/{id} — event, engagement_id, agent_type, tone, re_engagement_level, trigger_event, suppression_reason, timestamp
users/{uid}/daily_plans/{YYYY-MM-DD}  — plan_date, timezone, plan_source ("query_based"|"news_fallback"|"safe_default"), morning_nudge{topic,title,body,send_at_local_time,send_at_utc,why_this_topic,opening_chat_message,quick_reply_chips,status,cloud_task_name,sent_at}, evening_nudge{same}, rejection_feedback?, retry_count, created_at
```

**Engagement system** (`src/services/engagement/`): `orchestrator.py` (full pipeline), `decision_engine.py` (zero-LLM routing), `task_scheduler.py` (Cloud Tasks), `agent_registry.py`, `agents/` (4 specialists). Endpoints: `POST /internal/engage/orchestrate|notify` (OIDC-gated), `POST /internal/engage/responded` (Firebase Auth). Notification tap → `NotificationService.engagementTapStream` → `HomeViewModel.loadWithEngagementContext()`.

**SQLite (Drift) — local chat DB** (`juno_chat`, schema v4):
- `chat_messages` columns include `feedback`, `status`, `error_reason` (v3), `engagement_id`, `engagement_agent` (v4). After schema changes run `flutter pub run build_runner build --delete-conflicting-outputs`.
- Always use `AppLogger.warning()` (not `warn`). Use `showFlashAlert()` (not SnackBar) for brief confirmations.

---

## Working Style

**Planning:** Enter plan mode for any non-trivial task (2+ steps). Write specs upfront. Stop and re-plan if something goes sideways. Always get approval before implementing. Ask clarifying questions if you are not 100% sure about anything.

**Subagents:** Use liberally — offload research, exploration, and parallel analysis to keep main context clean.

**Verification:** Never mark a task complete without proving it works. Ask: "Would a staff engineer approve this?"

**Core principles:**
- Simplicity first — make every change as simple as possible
- Find root causes, no temporary fixes
- Minimal impact — only touch what's necessary
- Always refer to latest documentation; never use deprecated packages

NEVER push code to git, guide user instead. NEVER create branches without user consent. NEVER commit unless explicitly asked.
