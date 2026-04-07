import '../../core/base/safe_change_notifier.dart';
import '../../core/errors/app_exception.dart';
import '../../core/logging/app_logger.dart';
import '../../data/models/connector_models.dart';
import '../../data/services/google_calendar_connector_service.dart';
import 'view_state.dart';

export 'view_state.dart';

class ConnectorsViewModel extends SafeChangeNotifier {
  final GoogleCalendarConnectorService _connectorService;

  ViewState _state = ViewState.idle;
  GoogleCalendarConnectorStatus _googleCalendar =
      const GoogleCalendarConnectorStatus(
        enabled: false,
        watchActive: false,
        automaticSyncAvailable: false,
        webhookUrlConfigured: false,
        calendarId: 'primary',
        calendarName: 'Primary',
        calendarTimeZone: null,
        connectedAt: null,
        lastSyncedAt: null,
        lastSyncStatus: null,
        watchExpiresAt: null,
        pendingSync: false,
        lastError: null,
      );
  AppException? _error;
  bool _isMutating = false;

  ConnectorsViewModel({
    required GoogleCalendarConnectorService connectorService,
  }) : _connectorService = connectorService;

  ViewState get state => _state;
  GoogleCalendarConnectorStatus get googleCalendar => _googleCalendar;
  AppException? get error => _error;
  bool get isMutating => _isMutating;

  void _setState(ViewState value) {
    _state = value;
    safeNotifyListeners();
  }

  Future<void> load() async {
    _setState(ViewState.loading);
    final result = await _connectorService.fetchConnectors();
    result.when(
      success: (catalog) {
        _googleCalendar = catalog.googleCalendar;
        _error = null;
        _setState(ViewState.loaded);
      },
      failure: (error) {
        _error = error;
        _setState(ViewState.error);
      },
    );
  }

  Future<void> toggleGoogleCalendar(bool enabled) async {
    _isMutating = true;
    safeNotifyListeners();

    final result = enabled
        ? await _connectorService.connectGoogleCalendar()
        : await _connectorService.disconnectGoogleCalendar();

    result.when(
      success: (status) {
        _googleCalendar = status;
        _error = null;
        _state = ViewState.loaded;
      },
      failure: (error) {
        _error = error;
        _state = ViewState.error;
        AppLogger.error(
          'Google Calendar toggle failed',
          error: error,
          tag: 'ConnectorsVM',
        );
      },
    );

    _isMutating = false;
    safeNotifyListeners();
  }

  Future<void> syncGoogleCalendar() async {
    _isMutating = true;
    safeNotifyListeners();

    final result = await _connectorService.syncGoogleCalendar();
    result.when(
      success: (status) {
        _googleCalendar = status;
        _error = null;
        _state = ViewState.loaded;
      },
      failure: (error) {
        _error = error;
        _state = ViewState.error;
        AppLogger.error(
          'Manual Google Calendar sync failed',
          error: error,
          tag: 'ConnectorsVM',
        );
      },
    );

    _isMutating = false;
    safeNotifyListeners();
  }

  void clearError() {
    _error = null;
    safeNotifyListeners();
  }
}
