import 'package:flutter/foundation.dart';
import '../../core/errors/app_exception.dart';
import '../../core/errors/error_handler.dart';
import '../../core/logging/app_logger.dart';
import '../../data/services/lambda_api_service.dart';
import 'view_state.dart';

export 'view_state.dart';

enum MicState { idle, listening, processing }

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  const ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}

class HomeViewModel extends ChangeNotifier {
  final LambdaApiService _lambdaService;

  HomeViewModel({required LambdaApiService lambdaService})
      : _lambdaService = lambdaService;

  ViewState _state = ViewState.idle;
  MicState _micState = MicState.idle;
  AppException? _error;
  final List<ChatMessage> _messages = [];
  bool _isOffline = false;

  ViewState get state => _state;
  MicState get micState => _micState;
  AppException? get error => _error;
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isOffline => _isOffline;

  void _setState(ViewState s) {
    _state = s;
    notifyListeners();
  }

  void setMicState(MicState s) {
    _micState = s;
    notifyListeners();
  }

  void setOfflineStatus(bool offline) {
    _isOffline = offline;
    notifyListeners();
  }

  Future<void> sendMessage(String text, String userId) async {
    if (text.trim().isEmpty) return;

    _messages.add(ChatMessage(
      text: text.trim(),
      isUser: true,
      timestamp: DateTime.now(),
    ));
    _setState(ViewState.loading);

    try {
      final result = await _lambdaService.sendMessage(text.trim(), userId);
      result.when(
        success: (response) {
          _messages.add(ChatMessage(
            text: response.text,
            isUser: false,
            timestamp: DateTime.now(),
          ));
          _error = null;
          _setState(ViewState.loaded);
          ErrorHandler.logBreadcrumb('message_sent');
        },
        failure: (error) {
          _error = error;
          _setState(ViewState.error);
          AppLogger.error('Send message failed', error: error, tag: 'HomeVM');
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
    if (_state == ViewState.error) {
      _setState(_messages.isEmpty ? ViewState.idle : ViewState.loaded);
    } else {
      notifyListeners();
    }
  }

  void clearMessages() {
    _messages.clear();
    _setState(ViewState.idle);
  }
}
