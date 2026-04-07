import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../core/base/safe_change_notifier.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/errors/error_handler.dart';
import '../../core/logging/app_logger.dart';
import '../../data/local/app_database.dart';
import '../../data/models/chat_message_model.dart';
import '../../data/models/voice_models.dart';
import '../../data/repositories/chat_repository.dart';
import '../../data/services/lambda_api_service.dart';
import '../../data/services/voice_capture_service.dart';
import '../../data/services/voice_playback_service.dart';
import '../../data/services/voice_session_service.dart';
import '../../data/services/wake_word_service.dart';
import '../../core/network/connectivity_service.dart';
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
  bool _sessionTitleSet = false;

  HomeViewModel({
    required LambdaApiService lambdaService,
    required ConnectivityService connectivityService,
    required VoiceSessionService voiceSessionService,
    required VoiceCaptureService voiceCaptureService,
    required VoicePlaybackService voicePlaybackService,
    required WakeWordService wakeWordService,
    required ChatRepository chatRepository,
  })  : _lambdaService = lambdaService,
        _connectivityService = connectivityService,
        _voiceSessionService = voiceSessionService,
        _voiceCaptureService = voiceCaptureService,
        _voicePlaybackService = voicePlaybackService,
        _wakeWordService = wakeWordService,
        _chatRepository = chatRepository {
    _connectivitySubscription = _connectivityService.statusStream.listen(
      (status) {
        _isOffline = status == ConnectivityStatus.disconnected;
        safeNotifyListeners();
      },
    );
    _voiceEventsSubscription = _voiceSessionService.events.listen(_handleVoiceEvent);
    _primeConnectivityState();
  }

  // ── Public state ──────────────────────────────────────────────────────────

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

  // ── Initialisation ────────────────────────────────────────────────────────

  /// Must be called once after the user is authenticated.
  /// Restores the last session's messages so the UI is populated on cold start,
  /// without a network call.
  Future<void> initSession() async {
    final sessionsResult = await _chatRepository.loadRecentSessions(limit: 25);
    await sessionsResult.when(
      success: (sessions) async {
        _sessions = sessions;
        if (sessions.isNotEmpty) {
          await _loadSession(sessions.first.id);
        } else {
          await _openNewSession();
          safeNotifyListeners();
        }
      },
      failure: (e) async {
        AppLogger.error('Failed to load sessions', error: e, tag: 'HomeVM');
        await _openNewSession();
        safeNotifyListeners();
      },
    );
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

  /// Start wake word detection. Call after [initSession].
  Future<void> initWakeWord(String userId) async {
    await _wakeWordService.start(() => startVoiceSession(userId));
    AppLogger.info(
      'Wake word detection active',
      tag: 'HomeViewModel',
      metadata: {'userId': userId},
    );
  }

  // ── Voice session ─────────────────────────────────────────────────────────

  Future<void> startVoiceSession(String userId) async {
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

  // ── Text chat ─────────────────────────────────────────────────────────────

  Future<void> sendMessage(String text, String userId) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

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
    _addAndPersist(userMsg);
    _setState(ViewState.loading);

    // Set session title from first user message (fire and forget).
    if (!_sessionTitleSet && _currentSessionId != null) {
      _sessionTitleSet = true;
      unawaited(
        _chatRepository.setSessionTitle(
          _currentSessionId!,
          trimmed.length > 60 ? '${trimmed.substring(0, 57)}…' : trimmed,
        ).then((_) => _refreshSessions()),
      );
    }

    try {
      final result = await _lambdaService.sendMessage(
        trimmed,
        userId,
        history: _buildHistory(exclude: userMsg),
      );
      result.when(
        success: (response) {
          final assistantMsg = ChatMessageModel(
            id: _uuid.v4(),
            text: response.text,
            isUser: false,
            timestamp: DateTime.now(),
            channel: ChatMessageChannel.text,
            sessionId: _currentSessionId,
          );
          _addAndPersist(assistantMsg);
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
      _error = AppException.unexpected(e.toString(), error: e, stackTrace: st);
      _setState(ViewState.error);
    }
  }

  Future<void> sendLiveTextInput(String text) async {
    if (!hasActiveVoiceSession) {
      _error = AppException.unexpected('Start a live voice session before sending realtime text.');
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
    _addAndPersist(msg);
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

  // ── Session lifecycle ─────────────────────────────────────────────────────

  void clearError() {
    _error = null;
    if (_state == ViewState.error) {
      _setState(_messages.isEmpty ? ViewState.idle : ViewState.loaded);
    } else {
      safeNotifyListeners();
    }
  }

  /// Ends the current session (history is preserved) and opens a fresh one.
  void clearMessages() {
    unawaited(createNewChat());
  }

  // ── Voice event handler ───────────────────────────────────────────────────

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
          final msg = ChatMessageModel(
            id: _uuid.v4(),
            text: finalText,
            isUser: false,
            timestamp: DateTime.now(),
            channel: ChatMessageChannel.voice,
            sessionId: _currentSessionId,
          );
          _addAndPersist(msg);
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
          final msg = ChatMessageModel(
            id: _uuid.v4(),
            text: _streamingAssistantText.trim(),
            isUser: false,
            timestamp: DateTime.now(),
            channel: ChatMessageChannel.voice,
            sessionId: _currentSessionId,
          );
          _addAndPersist(msg);
        }
        _streamingAssistantText = '';
        _resetVoiceSessionState();
        _state = _messages.isEmpty ? ViewState.idle : ViewState.loaded;
        safeNotifyListeners();
        break;
    }
  }

  // ── Private helpers ───────────────────────────────────────────────────────

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
    final result = await _chatRepository.loadRecentSessions(limit: 25);
    result.when(
      success: (sessions) {
        _sessions = sessions;
        safeNotifyListeners();
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

  /// Adds [msg] to the in-memory list and fire-and-forgets a DB write.
  void _addAndPersist(ChatMessageModel msg) {
    _messages.add(msg);
    if (msg.sessionId != null) {
      unawaited(_chatRepository.saveMessage(msg).catchError(
        (Object e) => AppLogger.error(
          'Failed to persist message',
          error: e,
          tag: 'HomeVM',
        ),
      ));
    }
  }

  /// Opens a brand-new DB session and resets title tracking.
  Future<void> _openNewSession() async {
    try {
      _currentSessionId = await _chatRepository.createSession();
      _sessionTitleSet = false;
      await _refreshSessions();
    } catch (e) {
      AppLogger.error('Failed to create chat session', error: e, tag: 'HomeVM');
    }
  }

  /// Returns the last [chatHistoryWindow] messages (excluding [exclude]) as
  /// `[{role, content}]` for the backend Claude prompt.
  List<Map<String, String>> _buildHistory({ChatMessageModel? exclude}) {
    final window = AppConstants.chatHistoryWindow;
    final source = _messages.where((m) => m != exclude).toList();
    final slice = source.length > window
        ? source.sublist(source.length - window)
        : source;
    return slice.map((m) => m.toHistoryTurn()).toList();
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
