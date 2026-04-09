import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../core/base/safe_change_notifier.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/errors/error_handler.dart';
import '../../core/logging/app_logger.dart';
import '../../core/network/connectivity_service.dart';
import '../../data/local/app_database.dart';
import '../../data/models/chat_message_model.dart';
import '../../data/models/voice_models.dart';
import '../../data/repositories/chat_repository.dart';
import '../../data/services/chat_backup_service.dart';
import '../../data/services/feedback_service.dart';
import '../../data/services/lambda_api_service.dart';
import '../../data/services/voice_capture_service.dart';
import '../../data/services/voice_playback_service.dart';
import '../../data/services/voice_session_service.dart';
import '../../data/services/wake_word_service.dart';
import 'view_state.dart';

export 'view_state.dart';

enum MicState { idle, listening, processing }

class HomeViewModel extends SafeChangeNotifier {
  final LambdaApiService _lambdaService;
  final ConnectivityService _connectivityService;
  final VoiceSessionService _voiceSessionService;
  final VoiceCaptureService _voiceCaptureService;
  final VoicePlaybackService _voicePlaybackService;
  final WakeWordService _wakeWordService;
  final ChatRepository _chatRepository;
  final ChatBackupService _chatBackupService;
  final FeedbackService _feedbackService;
  final Uuid _uuid = const Uuid();

  StreamSubscription<ConnectivityStatus>? _connectivitySubscription;
  StreamSubscription<VoiceServerEvent>? _voiceEventsSubscription;

  ViewState _state = ViewState.idle;
  MicState _micState = MicState.idle;
  VoiceSessionStatus _voiceStatus = VoiceSessionStatus.disconnected;
  AppException? _error;
  final List<ChatMessageModel> _messages = [];
  List<ChatSession> _sessions = const [];
  bool _isOffline = false;
  String _streamingAssistantText = '';
  String? _activeVoiceSessionId;
  String? _currentSessionId;
  String? _currentUserId;
  bool _sessionTitleSet = false;

  HomeViewModel({
    required LambdaApiService lambdaService,
    required ConnectivityService connectivityService,
    required VoiceSessionService voiceSessionService,
    required VoiceCaptureService voiceCaptureService,
    required VoicePlaybackService voicePlaybackService,
    required WakeWordService wakeWordService,
    required ChatRepository chatRepository,
    required ChatBackupService chatBackupService,
    required FeedbackService feedbackService,
  })  : _lambdaService = lambdaService,
        _connectivityService = connectivityService,
        _voiceSessionService = voiceSessionService,
        _voiceCaptureService = voiceCaptureService,
        _voicePlaybackService = voicePlaybackService,
        _wakeWordService = wakeWordService,
        _chatRepository = chatRepository,
        _chatBackupService = chatBackupService,
        _feedbackService = feedbackService {
    _connectivitySubscription = _connectivityService.statusStream.listen(
      (status) {
        _isOffline = status == ConnectivityStatus.disconnected;
        safeNotifyListeners();
      },
    );
    _voiceEventsSubscription = _voiceSessionService.events.listen(_handleVoiceEvent);
    _primeConnectivityState();
  }

  ViewState get state => _state;
  MicState get micState => _micState;
  VoiceSessionStatus get voiceStatus => _voiceStatus;
  AppException? get error => _error;
  List<ChatMessageModel> get messages => List.unmodifiable(_messages);
  List<ChatSession> get sessions => List.unmodifiable(_sessions);
  bool get isOffline => _isOffline;
  String get streamingAssistantText => _streamingAssistantText;
  String? get currentSessionId => _currentSessionId;
  bool get hasActiveVoiceSession =>
      _voiceStatus != VoiceSessionStatus.disconnected &&
      _voiceStatus != VoiceSessionStatus.ended &&
      _voiceStatus != VoiceSessionStatus.error;
  String? get activeVoiceSessionId => _activeVoiceSessionId;
  bool get isVoiceCaptureAvailable => _voiceCaptureService.isSupported;

  Future<void> initSession(String? userId) async {
    _currentUserId = _normalizeUserId(userId);

    await _loadRecentSessions();

    if (_sessions.isEmpty && _currentUserId != null) {
      await _chatBackupService.restoreFromBackupIfLocalEmpty(_currentUserId!);
      await _loadRecentSessions();
    }

    if (_sessions.isNotEmpty) {
      await _loadSession(_sessions.first.id);
    } else {
      await _openNewSession();
      safeNotifyListeners();
    }

    if (_currentUserId != null) {
      unawaited(_chatBackupService.processPendingJobs(userId: _currentUserId));
    }
  }

  Future<void> switchSession(String sessionId) async {
    if (_currentSessionId == sessionId) return;
    if (hasActiveVoiceSession) {
      await cancelVoiceSession();
    }
    await _loadSession(sessionId);
  }

  Future<void> createNewChat() async {
    if (hasActiveVoiceSession) {
      await cancelVoiceSession();
    }
    _messages.clear();
    _streamingAssistantText = '';
    _error = null;
    await _openNewSession();
    _setState(ViewState.idle);
    await _refreshSessions();
  }

  Future<void> initWakeWord(String userId) async {
    await _wakeWordService.start(() => startVoiceSession(userId));
    AppLogger.info(
      'Wake word detection active',
      tag: 'HomeViewModel',
      metadata: {'userId': userId},
    );
  }

  Future<void> startVoiceSession(String userId) async {
    _currentUserId = _normalizeUserId(userId);
    if (hasActiveVoiceSession) return;

    _error = null;
    _voiceStatus = VoiceSessionStatus.connecting;
    _micState = MicState.listening;
    safeNotifyListeners();

    final result = await _voiceSessionService.startSession(
      VoiceSessionConfig(userId: userId),
    );

    await result.when(
      success: (_) async {
        if (_voiceCaptureService.isSupported) {
          await _voiceCaptureService.start((audioBytes) {
            unawaited(_voiceSessionService.sendAudioChunk(audioBytes));
          });
        }
        ErrorHandler.logBreadcrumb('voice_session_started', metadata: {'userId': userId});
      },
      failure: (error) async {
        _error = error;
        _voiceStatus = VoiceSessionStatus.error;
        _micState = MicState.idle;
        safeNotifyListeners();
      },
    );
  }

  Future<void> stopVoiceSession() async {
    if (!hasActiveVoiceSession) return;

    await _voiceCaptureService.stop();
    _voiceStatus = VoiceSessionStatus.processing;
    _micState = MicState.processing;
    safeNotifyListeners();

    final result = await _voiceSessionService.endInput();
    result.when(
      success: (_) {
        ErrorHandler.logBreadcrumb(
          'voice_session_input_ended',
          metadata: {'sessionId': _activeVoiceSessionId},
        );
      },
      failure: (error) {
        _error = error;
        _voiceStatus = VoiceSessionStatus.error;
        _micState = MicState.idle;
        safeNotifyListeners();
      },
    );
  }

  Future<void> cancelVoiceSession() async {
    await _voiceCaptureService.stop();
    await _voiceSessionService.close();
    _resetVoiceSessionState();
    safeNotifyListeners();
  }

  Future<void> sendMessage(String text, String userId) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    _currentUserId = _normalizeUserId(userId);

    if (hasActiveVoiceSession) {
      await sendLiveTextInput(trimmed);
      return;
    }

    final userMsg = ChatMessageModel(
      id: _uuid.v4(),
      text: trimmed,
      isUser: true,
      timestamp: DateTime.now(),
      channel: ChatMessageChannel.text,
      sessionId: _currentSessionId,
    );

    final savedUserMessage = await _persistMessage(userMsg);
    if (!savedUserMessage) return;

    _setState(ViewState.loading);

    if (!_sessionTitleSet && _currentSessionId != null) {
      _sessionTitleSet = true;
      final title = trimmed.length > 60 ? '${trimmed.substring(0, 57)}...' : trimmed;
      unawaited(_persistSessionTitle(_currentSessionId!, title));
    }

    await _sendAndHandleResponse(trimmed, userMsg);
  }

  /// Retries the last failed response. Finds the user message that preceded
  /// the error response and re-sends it.
  Future<void> retryLastResponse(String errorMessageId) async {
    if (_currentUserId == null) return;

    // Find the error message and the user message before it
    final errorIndex = _messages.indexWhere((m) => m.id == errorMessageId);
    if (errorIndex < 0) return;

    final errorMsg = _messages[errorIndex];
    if (errorMsg.status != MessageStatus.error) return;

    // Find the preceding user message
    ChatMessageModel? userMsg;
    for (var i = errorIndex - 1; i >= 0; i--) {
      if (_messages[i].isUser) {
        userMsg = _messages[i];
        break;
      }
    }
    if (userMsg == null) return;

    // Remove the error message from local state + DB
    _messages.removeAt(errorIndex);
    safeNotifyListeners();

    _setState(ViewState.loading);
    await _sendAndHandleResponse(userMsg.text, userMsg);
  }

  /// Edits a user message: updates its text, deletes all messages after it,
  /// and re-sends to get a fresh response.
  Future<void> editAndResend(String messageId, String newText) async {
    if (_currentUserId == null) return;

    final msgIndex = _messages.indexWhere((m) => m.id == messageId);
    if (msgIndex < 0) return;

    final oldMsg = _messages[msgIndex];
    if (!oldMsg.isUser) return;

    // Update the message content locally
    final updatedMsg = oldMsg.copyWith(text: newText);
    _messages[msgIndex] = updatedMsg;

    // Remove all messages after this one
    if (msgIndex + 1 < _messages.length) {
      _messages.removeRange(msgIndex + 1, _messages.length);
    }
    safeNotifyListeners();

    // Persist: update content in DB + delete subsequent messages
    await _chatRepository.updateMessageContent(messageId, newText);
    final seq = await _chatRepository.getMessageSequence(messageId);
    if (seq != null && _currentSessionId != null) {
      await _chatRepository.deleteMessagesAfter(_currentSessionId!, seq);
    }

    // Re-send
    _setState(ViewState.loading);
    await _sendAndHandleResponse(newText, updatedMsg);
  }

  /// Toggles feedback on an assistant message.
  /// Persists locally (SQLite) and remotely (Firestore).
  Future<void> setFeedback(String messageId, MessageFeedback? feedback) async {
    final msgIndex = _messages.indexWhere((m) => m.id == messageId);
    if (msgIndex < 0) return;

    final msg = _messages[msgIndex];
    if (msg.isUser) return;

    // Update in-memory
    _messages[msgIndex] = msg.copyWith(feedback: () => feedback);
    safeNotifyListeners();

    // Persist locally
    await _chatRepository.updateFeedback(messageId, feedback);

    // Sync to Firestore (fire-and-forget)
    if (_currentUserId != null && _currentSessionId != null) {
      unawaited(_feedbackService.saveFeedback(
        userId: _currentUserId!,
        messageId: messageId,
        sessionId: _currentSessionId!,
        feedback: feedback,
        messageContent: msg.text,
      ));
    }
  }

  Future<void> sendLiveTextInput(String text) async {
    if (!hasActiveVoiceSession) {
      _error = AppException.unexpected(
        'Start a live voice session before sending realtime text.',
      );
      safeNotifyListeners();
      return;
    }

    final msg = ChatMessageModel(
      id: _uuid.v4(),
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
      channel: ChatMessageChannel.voice,
      sessionId: _currentSessionId,
    );

    final saved = await _persistMessage(msg);
    if (!saved) return;

    _streamingAssistantText = '';
    _voiceStatus = VoiceSessionStatus.processing;
    _micState = MicState.processing;
    safeNotifyListeners();

    final sendResult = await _voiceSessionService.sendTextInput(text);
    final endResult = await _voiceSessionService.endInput();

    final sendError = sendResult.errorOrNull ?? endResult.errorOrNull;
    if (sendError != null) {
      _error = sendError;
      _voiceStatus = VoiceSessionStatus.error;
      _micState = MicState.idle;
      safeNotifyListeners();
    }
  }

  Future<void> sendOcrContext(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || !hasActiveVoiceSession) return;
    await _voiceSessionService.sendOcrContext(trimmed);
  }

  void clearError() {
    _error = null;
    if (_state == ViewState.error) {
      _setState(_messages.isEmpty ? ViewState.idle : ViewState.loaded);
    } else {
      safeNotifyListeners();
    }
  }

  void clearMessages() {
    unawaited(createNewChat());
  }

  void _handleVoiceEvent(VoiceServerEvent event) {
    switch (event.type) {
      case 'session.ready':
        _activeVoiceSessionId = event.sessionId;
        _voiceStatus = VoiceSessionStatus.ready;
        _micState = _voiceCaptureService.isSupported
            ? MicState.listening
            : MicState.processing;
        _error = null;
        safeNotifyListeners();
        break;
      case 'session.state':
        final stateValue = event.payload?['state'] as String?;
        if (stateValue == 'listening') {
          _voiceStatus = VoiceSessionStatus.listening;
          _micState = MicState.listening;
        } else if (stateValue == 'speaking') {
          _voiceStatus = VoiceSessionStatus.speaking;
          _micState = MicState.processing;
        } else if (stateValue == 'processing') {
          _voiceStatus = VoiceSessionStatus.processing;
          _micState = MicState.processing;
        }
        safeNotifyListeners();
        break;
      case 'assistant.text.delta':
        _voiceStatus = VoiceSessionStatus.speaking;
        _streamingAssistantText += event.text ?? '';
        safeNotifyListeners();
        break;
      case 'assistant.text.final':
        final finalText = (event.text ?? _streamingAssistantText).trim();
        if (finalText.isNotEmpty) {
          unawaited(_persistGeneratedVoiceMessage(finalText));
        }
        _streamingAssistantText = '';
        _state = ViewState.loaded;
        safeNotifyListeners();
        break;
      case 'assistant.audio.chunk':
        unawaited(
          _voicePlaybackService.enqueueAudio(
            audioBase64: event.audioBase64 ?? '',
            mimeType: event.mimeType ?? 'audio/lpcm',
            sampleRateHertz: event.sampleRateHertz,
          ),
        );
        break;
      case 'tool.call':
        ErrorHandler.logBreadcrumb(
          'voice_tool_call',
          metadata: <String, dynamic>{
            'toolName': event.toolName,
            'sessionId': event.sessionId,
          },
        );
        break;
      case 'tool.result':
        ErrorHandler.logBreadcrumb(
          'voice_tool_result',
          metadata: <String, dynamic>{
            'toolName': event.toolName,
            'sessionId': event.sessionId,
          },
        );
        break;
      case 'error':
        _error = AppException.unexpected(event.message ?? 'Voice session failed.');
        _voiceStatus = VoiceSessionStatus.error;
        _micState = MicState.idle;
        safeNotifyListeners();
        break;
      case 'session.ended':
        if (_streamingAssistantText.trim().isNotEmpty) {
          unawaited(_persistGeneratedVoiceMessage(_streamingAssistantText.trim()));
        }
        _streamingAssistantText = '';
        _resetVoiceSessionState();
        _state = _messages.isEmpty ? ViewState.idle : ViewState.loaded;
        safeNotifyListeners();
        break;
    }
  }

  Future<void> _loadSession(String sessionId) async {
    _currentSessionId = sessionId;
    _messages.clear();
    _streamingAssistantText = '';

    ChatSession? session;
    for (final item in _sessions) {
      if (item.id == sessionId) {
        session = item;
        break;
      }
    }
    _sessionTitleSet = session?.title != null;

    final msgsResult = await _chatRepository.loadMessages(sessionId);
    msgsResult.when(
      success: (msgs) {
        _messages
          ..clear()
          ..addAll(msgs);
        _state = _messages.isEmpty ? ViewState.idle : ViewState.loaded;
        _error = null;
        safeNotifyListeners();
      },
      failure: (e) {
        AppLogger.error(
          'Failed to restore messages',
          error: e,
          tag: 'HomeVM',
        );
        _state = ViewState.error;
        _error = e;
        safeNotifyListeners();
      },
    );
  }

  Future<void> _refreshSessions() async {
    await _loadRecentSessions(notify: true);
  }

  Future<void> _loadRecentSessions({bool notify = false}) async {
    final result = await _chatRepository.loadRecentSessions(limit: 25);
    result.when(
      success: (sessions) {
        _sessions = sessions;
        if (notify) {
          safeNotifyListeners();
        }
      },
      failure: (error) {
        AppLogger.error(
          'Failed to refresh sessions',
          error: error,
          tag: 'HomeVM',
        );
      },
    );
  }

  void _setState(ViewState nextState) {
    _state = nextState;
    safeNotifyListeners();
  }

  Future<void> _primeConnectivityState() async {
    _isOffline = !await _connectivityService.isConnected;
    safeNotifyListeners();
  }

  void _resetVoiceSessionState() {
    _voiceStatus = VoiceSessionStatus.disconnected;
    _micState = MicState.idle;
    _activeVoiceSessionId = null;
  }

  Future<bool> _persistMessage(ChatMessageModel msg) async {
    _messages.add(msg);
    safeNotifyListeners();

    final result = await _chatRepository.saveMessage(
      msg,
      userId: _currentUserId,
    );

    if (result.isFailure) {
      _messages.remove(msg);
      final error = result.errorOrNull ??
          AppException.unexpected('Failed to persist chat message locally.');
      _error = error;
      _state = ViewState.error;
      AppLogger.error(
        'Failed to persist message locally',
        error: error,
        tag: 'HomeVM',
        metadata: {'messageId': msg.id, 'sessionId': msg.sessionId},
      );
      safeNotifyListeners();
      return false;
    }

    return true;
  }

  Future<void> _persistSessionTitle(String sessionId, String title) async {
    final result = await _chatRepository.setSessionTitle(
      sessionId,
      title,
      userId: _currentUserId,
    );

    result.when(
      success: (_) {
        unawaited(_refreshSessions());
      },
      failure: (error) {
        AppLogger.error(
          'Failed to persist session title locally',
          error: error,
          tag: 'HomeVM',
          metadata: {'sessionId': sessionId},
        );
      },
    );
  }

  Future<void> _persistGeneratedVoiceMessage(String text) async {
    final msg = ChatMessageModel(
      id: _uuid.v4(),
      text: text,
      isUser: false,
      timestamp: DateTime.now(),
      channel: ChatMessageChannel.voice,
      sessionId: _currentSessionId,
    );
    await _persistMessage(msg);
  }

  Future<void> _openNewSession() async {
    try {
      _currentSessionId = await _chatRepository.createSession();
      _sessionTitleSet = false;
      await _refreshSessions();
    } catch (e) {
      AppLogger.error('Failed to create chat session', error: e, tag: 'HomeVM');
    }
  }

  /// Shared helper: send user message to API and handle success/failure.
  /// Extracts the duplicated pattern from sendMessage, retryLastResponse,
  /// and editAndResend.
  Future<void> _sendAndHandleResponse(
    String text,
    ChatMessageModel userMsg,
  ) async {
    try {
      final result = await _lambdaService.sendMessage(
        text,
        _currentUserId!,
        history: _buildHistory(exclude: userMsg),
        sessionId: _currentSessionId,
      );

      await result.when(
        success: (response) async {
          final assistantMsg = ChatMessageModel(
            id: _uuid.v4(),
            text: response.text,
            isUser: false,
            timestamp: DateTime.now(),
            channel: ChatMessageChannel.text,
            sessionId: _currentSessionId,
          );

          final savedAssistantMessage = await _persistMessage(assistantMsg);
          if (!savedAssistantMessage) return;

          _error = null;
          _setState(ViewState.loaded);
          ErrorHandler.logBreadcrumb('message_sent');
        },
        failure: (error) async {
          // Create an error assistant message with the failure reason
          final errorMsg = ChatMessageModel(
            id: _uuid.v4(),
            text: '',
            isUser: false,
            timestamp: DateTime.now(),
            channel: ChatMessageChannel.text,
            sessionId: _currentSessionId,
            status: MessageStatus.error,
            errorReason: _userFriendlyError(error),
          );

          await _persistMessage(errorMsg);
          _error = error;
          _setState(ViewState.error);
          AppLogger.error('Send message failed', error: error, tag: 'HomeVM');
        },
      );
    } catch (e, st) {
      ErrorHandler.handle(e, st);

      final errorMsg = ChatMessageModel(
        id: _uuid.v4(),
        text: '',
        isUser: false,
        timestamp: DateTime.now(),
        channel: ChatMessageChannel.text,
        sessionId: _currentSessionId,
        status: MessageStatus.error,
        errorReason: _userFriendlyError(
          AppException.unexpected(e.toString(), error: e, stackTrace: st),
        ),
      );
      await _persistMessage(errorMsg);

      _error = AppException.unexpected(e.toString(), error: e, stackTrace: st);
      _setState(ViewState.error);
    }
  }

  List<Map<String, String>> _buildHistory({ChatMessageModel? exclude}) {
    final window = AppConstants.chatHistoryWindow;
    final source = _messages
        .where((m) => m != exclude && m.status != MessageStatus.error)
        .toList();
    final slice = source.length > window
        ? source.sublist(source.length - window)
        : source;
    return slice.map((m) => m.toHistoryTurn()).toList();
  }

  String? _normalizeUserId(String? userId) {
    if (userId == null) return null;
    final trimmed = userId.trim();
    if (trimmed.isEmpty || trimmed == 'anonymous') {
      return null;
    }
    return trimmed;
  }

  /// Converts AppException to a user-friendly error message.
  static String _userFriendlyError(AppException error) {
    final msg = error.message.toLowerCase();
    if (msg.contains('overloaded') || msg.contains('529')) {
      return 'The AI service is temporarily overloaded. Please retry in a moment.';
    }
    if (msg.contains('timeout') || msg.contains('timed out')) {
      return 'The request timed out. Please check your connection and retry.';
    }
    if (msg.contains('network') || msg.contains('connection')) {
      return 'Network error. Please check your internet connection and retry.';
    }
    if (msg.contains('rate limit') || msg.contains('429')) {
      return 'Too many requests. Please wait a moment and retry.';
    }
    return 'Something went wrong. Please try again.';
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _voiceEventsSubscription?.cancel();
    unawaited(_wakeWordService.stop());
    unawaited(_voiceSessionService.dispose());
    super.dispose();
  }
}
