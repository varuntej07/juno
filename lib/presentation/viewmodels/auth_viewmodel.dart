import 'dart:async';

import '../../core/base/safe_change_notifier.dart';
import '../../core/errors/app_exception.dart';
import '../../core/errors/error_handler.dart';
import '../../core/logging/app_logger.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/services/notification_service.dart';
import 'view_state.dart';

export 'view_state.dart';

class AuthViewModel extends SafeChangeNotifier {
  final AuthRepository _authRepository;
  final NotificationService _notificationService;

  AuthViewModel({
    required AuthRepository authRepository,
    required NotificationService notificationService,
  })  : _authRepository = authRepository,
        _notificationService = notificationService;

  ViewState _state = ViewState.idle;
  UserModel? _user;
  AppException? _error;

  ViewState get state => _state;
  UserModel? get user => _user;
  AppException? get error => _error;
  bool get isAuthenticated => _user != null;

  void _setState(ViewState s) {
    _state = s;
    safeNotifyListeners();
  }

  Future<void> initialize() async {
    _setState(ViewState.loading);
    try {
      final result = await _authRepository.getCurrentUser();
      result.when(
        success: (user) {
          _user = user;
          if (user != null) {
            ErrorHandler.setUser(user.uid);
            // Register FCM token for the already-authenticated user.
            unawaited(_notificationService.initialize(user.uid));
          }
          _setState(ViewState.loaded);
        },
        failure: (error) {
          _error = error;
          _setState(ViewState.error);
          AppLogger.error('Initialize failed', error: error, tag: 'AuthVM');
        },
      );
    } catch (e, st) {
      ErrorHandler.handle(e, st);
      _error = AppException.unexpected(e.toString());
      _setState(ViewState.error);
    }
  }

  Future<void> signInWithGoogle() async {
    _setState(ViewState.loading);
    try {
      final result = await _authRepository.signInWithGoogle();
      result.when(
        success: (user) {
          _user = user;
          _error = null;
          ErrorHandler.setUser(user.uid);
          ErrorHandler.logBreadcrumb('user_signed_in', metadata: {'uid': user.uid});
          // Register FCM token for the freshly signed-in user.
          unawaited(_notificationService.initialize(user.uid));
          _setState(ViewState.loaded);
        },
        failure: (error) {
          _error = error;
          _setState(ViewState.error);
          AppLogger.error('Sign-in failed', error: error, tag: 'AuthVM');
        },
      );
    } catch (e, st) {
      ErrorHandler.handle(e, st);
      _error = AppException.unexpected(e.toString());
      _setState(ViewState.error);
    }
  }

  Future<void> signOut() async {
    _setState(ViewState.loading);
    try {
      final result = await _authRepository.signOut();
      result.when(
        success: (_) {
          _user = null;
          _error = null;
          ErrorHandler.logBreadcrumb('user_signed_out');
          _setState(ViewState.idle);
        },
        failure: (error) {
          _error = error;
          _setState(ViewState.error);
          AppLogger.error('Sign-out failed', error: error, tag: 'AuthVM');
        },
      );
    } catch (e, st) {
      ErrorHandler.handle(e, st);
      _error = AppException.unexpected(e.toString());
      _setState(ViewState.error);
    }
  }

  void clearError() {
    _error = null;
    safeNotifyListeners();
  }
}
