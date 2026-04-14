import '../../core/base/safe_change_notifier.dart';
import '../../core/logging/app_logger.dart';
import '../../data/models/reminder_model.dart';
import '../../data/repositories/reminder_repository.dart';
import 'view_state.dart';

class RemindersViewModel extends SafeChangeNotifier {
  final ReminderRepository _repository;

  RemindersViewModel({required ReminderRepository repository})
      : _repository = repository;

  ViewState _state = ViewState.idle;
  List<ReminderModel> _reminders = [];
  String? _errorMessage;
  bool _isLoadingMore = false;

  ViewState get state => _state;
  String? get errorMessage => _errorMessage;

  /// True while a subsequent page is being fetched (initial load uses [state]).
  bool get isLoadingMore => _isLoadingMore;

  /// Whether more pages exist in Firestore.
  bool get hasMore => _repository.hasMore;

  // ── Derived lists ───────────────────────────────────────────────────────────

  /// Pending / snoozed / fired reminders sorted soonest-first.
  /// "Fired" means the notification was delivered — not that the user
  /// has acknowledged it. They stay in Upcoming until explicitly dismissed.
  List<ReminderModel> get activeReminders => _reminders
      .where((r) => r.status.isActive)
      .toList()
    ..sort((a, b) => a.triggerAt.compareTo(b.triggerAt));

  /// Only explicitly dismissed reminders, sorted most-recent-first.
  List<ReminderModel> get completedReminders => _reminders
      .where((r) => r.status.isCompleted)
      .toList()
    ..sort((a, b) => b.triggerAt.compareTo(a.triggerAt));

  // ── Load ────────────────────────────────────────────────────────────────────

  /// Loads the first page. Always resets pagination and local state.
  Future<void> loadReminders(String userId) async {
    _state = ViewState.loading;
    _errorMessage = null;
    _reminders = [];
    _isLoadingMore = false;
    _repository.resetPagination();
    safeNotifyListeners();

    final result = await _repository.getNextPage(userId);
    result.when(
      success: (items) {
        _reminders = items;
        _state = ViewState.loaded;
        safeNotifyListeners();
      },
      failure: (error) {
        _errorMessage = error.message;
        _state = ViewState.error;
        AppLogger.error(
          'Failed to load reminders',
          error: error,
          tag: 'RemindersVM',
          metadata: {'userId': userId},
        );
        safeNotifyListeners();
      },
    );
  }

  /// Appends the next page. No-ops when already loading or no more pages.
  Future<void> loadMore(String userId) async {
    if (_isLoadingMore || !hasMore || _state != ViewState.loaded) return;

    _isLoadingMore = true;
    safeNotifyListeners();

    final result = await _repository.getNextPage(userId);
    result.when(
      success: (items) {
        _reminders.addAll(items);
        _isLoadingMore = false;
        safeNotifyListeners();
      },
      failure: (error) {
        _isLoadingMore = false;
        _errorMessage = error.message;
        AppLogger.error(
          'Failed to load more reminders',
          error: error,
          tag: 'RemindersVM',
          metadata: {'userId': userId},
        );
        safeNotifyListeners();
      },
    );
  }

  // ── Complete / undo ─────────────────────────────────────────────────────────

  /// Marks a reminder as dismissed (Google Tasks-style "complete").
  /// Optimistically updates local state so the UI is instant.
  Future<void> markComplete(String userId, String reminderId) async {
    final idx = _reminders.indexWhere((r) => r.id == reminderId);
    if (idx < 0) return;

    final original = _reminders[idx];
    _reminders[idx] = original.copyWith(
      status: ReminderStatus.dismissed,
      dismissedAt: DateTime.now(),
    );
    safeNotifyListeners();

    final result = await _repository.updateStatus(
      userId,
      reminderId,
      ReminderStatus.dismissed,
      dismissedAt: DateTime.now(),
    );

    result.when(
      success: (_) {},
      failure: (error) {
        _reminders[idx] = original;
        _errorMessage = error.message;
        AppLogger.error(
          'Failed to mark reminder complete',
          error: error,
          tag: 'RemindersVM',
          metadata: {'reminderId': reminderId},
        );
        safeNotifyListeners();
      },
    );
  }

  /// Reverts a dismissed reminder back to active — undoing an accidental tap.
  ///
  /// Restores to [ReminderStatus.fired] if the notification was already sent,
  /// otherwise [ReminderStatus.pending], preserving the original timeline.
  Future<void> markIncomplete(String userId, String reminderId) async {
    final idx = _reminders.indexWhere((r) => r.id == reminderId);
    if (idx < 0) return;

    final original = _reminders[idx];
    final restoredStatus = original.firedAt != null
        ? ReminderStatus.fired
        : ReminderStatus.pending;

    _reminders[idx] = original.copyWith(
      status: restoredStatus,
      dismissedAt: null, // sentinel in copyWith handles explicit null
    );
    safeNotifyListeners();

    final result = await _repository.updateStatus(
      userId,
      reminderId,
      restoredStatus,
      clearDismissedAt: true,
    );

    result.when(
      success: (_) {},
      failure: (error) {
        _reminders[idx] = original;
        _errorMessage = error.message;
        AppLogger.error(
          'Failed to undo reminder completion',
          error: error,
          tag: 'RemindersVM',
          metadata: {'reminderId': reminderId},
        );
        safeNotifyListeners();
      },
    );
  }

  // ── Misc ────────────────────────────────────────────────────────────────────

  void clearError() {
    _errorMessage = null;
    safeNotifyListeners();
  }
}
