## Architecture

### Frontend (Flutter/Dart) — MVVM Pattern
- **Views** (`frontend/lib/Views/`) — UI screens, one per feature. Views only read from ViewModels via `Consumer<>` or `context.watch<>()`; they never contain business logic.
- **ViewModels** (`frontend/lib/ViewModels/`) — business logic via `ChangeNotifier` + Provider. Always guard `notifyListeners()` with an `_isDisposed` flag using a `_safeNotifyListeners()` helper. Use `context.read<>()` for one-shot calls (e.g. button taps).
- **Services** (`frontend/lib/Services/`) — singleton HTTP clients (see `CreatorPostsService` as the canonical pattern). All errors must be logged to **Firebase Crashlytics** via `FirebaseCrashlytics.instance.recordError(...)`. Never throw to callers — return `null`/`false` on failure. Never gate error logging behind `kDebugMode` — this is a mobile app and all errors must reach Crashlytics in production. For HTTP success checks, always use `response.isSuccess` (from `Utils/http_utils.dart`) instead of `statusCode == 200` — it covers the full 2xx range (200, 201, 204, etc.).

**HTTP timeouts:** Every `http.get/post/delete` call must be chained with `.timeout(const Duration(seconds: 10))`. Always add a dedicated `on TimeoutException catch (e)` block that calls `_handleError('methodName (timeout)', e)` and returns `null`/`false` — this surfaces Render cold-start hangs in Crashlytics with a clear "timeout" label instead of a generic exception. The canonical reference is `TokenRefreshService` (10-second timeout with explicit `TimeoutException` catch). Import `dart:async` for `TimeoutException`.

**Crashlytics non-fatal errors:** `recordError()` logs to the **Non-fatal** tab in Firebase Console, NOT the Crashes tab. Always check Non-fatal/Events when debugging silent failures — the Crashes tab only shows process-killing fatal errors.
- **Models** (`frontend/lib/Models/`) — immutable Dart data classes with `fromMap`, `toMap`, `copyWith`, `==`, and `hashCode`. No business logic in models.
- **Widgets** (`frontend/lib/Widgets/`) — reusable UI components with no direct service/VM dependencies.

**Provider wiring:** ViewModels are provided via `ChangeNotifierProvider` or `MultiProvider` at the route level, not globally (except long-lived VMs like `AuthViewModel`). Never instantiate a ViewModel inside a `build` method.

**Current user identity:** `AuthViewModel` should be  the single source of truth for the current user's identity (`userProfile?.uid`, `userProfile?.username`, etc.). Never use `FirebaseAuth.instance.currentUser` directly in Views or ViewModels — it can be `null` during token refresh even for a logged-in user. Always access identity via `context.read<AuthViewModel>().userProfile?.uid` at the call site (e.g. navigation), then pass it as a constructor parameter to screens/ViewModels that need it.

## Working Style

**Planning:** Enter plan mode for any non-trivial task (2+ steps). Write detailed specs upfront. If something goes sideways, stop and re-plan before continuing.

**Subagents:** Use subagents liberally — offload research, exploration, and parallel analysis to keep the main context window clean. One focused task per subagent.

**Verification:** Never mark a task complete without proving it works. Run tests, check logs, diff behavior. Ask: "Would a staff engineer approve this?"

**Elegance:** For non-trivial changes, pause and ask "is there a simpler way?" or "knowing everything I know now, is this right?" Skip for simple, obvious fixes.

**Bug fixing:** When given a bug report, fix it autonomously — point at logs/errors/failing tests and resolve them without asking for permission.

**Core principles:**
- Simplicity first — make every change as simple as possible
- Find root causes, no temporary fixes
- Minimal impact — only touch what's necessary
- Track progress and mark tasks complete as you go

NEVER push code to git, guide user instead. NEVER create branches without getting user consent. NEVER commit code unless explicitly asked.
