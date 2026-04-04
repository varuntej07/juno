import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../core/constants/api_endpoints.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/logging/app_logger.dart';
import '../../core/network/api_response.dart';
import '../models/voice_models.dart';
import 'platform_web_socket.dart';

class VoiceSessionService {
  final Future<String?> Function() _tokenProvider;

  PlatformWebSocket? _socket;
  final StreamController<VoiceServerEvent> _eventsController =
      StreamController<VoiceServerEvent>.broadcast();
  StreamSubscription<dynamic>? _socketSubscription;
  String? _activeSessionId;

  VoiceSessionService({
    required Future<String?> Function() tokenProvider,
  }) : _tokenProvider = tokenProvider;

  Stream<VoiceServerEvent> get events => _eventsController.stream;
  bool get isConnected => _socket != null;
  String? get activeSessionId => _activeSessionId;

  Future<Result<void>> startSession(VoiceSessionConfig config) async {
    if (_socket != null) {
      return const Result.success(null);
    }

    try {
      final token = await _tokenProvider();
      final headers = <String, dynamic>{
        'x-juno-user-id': config.userId,
        if (token != null) 'Authorization': 'Bearer $token',
      };

      final socket = await connectPlatformWebSocket(
        ApiEndpoints.voiceStream,
        headers: headers,
        pingInterval: AppConstants.webSocketPingInterval,
      );

      _socket = socket;
      _socketSubscription = socket.stream.listen(
        _handleSocketData,
        onError: _handleSocketError,
        onDone: _handleSocketDone,
        cancelOnError: false,
      );

      await _sendJson({
        'type': 'session.start',
        'payload': config.toJson(),
      });

      AppLogger.info(
        'Voice session started',
        tag: 'VoiceSessionService',
        metadata: {'userId': config.userId},
      );
      return const Result.success(null);
    } catch (e, st) {
      AppLogger.error(
        'Failed to start voice session',
        error: e,
        stackTrace: st,
        tag: 'VoiceSessionService',
      );
      return Result.failure(
        AppException.unexpected(
          'Failed to connect to the realtime voice gateway.',
          error: e,
          stackTrace: st,
        ),
      );
    }
  }

  Future<Result<void>> sendTextInput(String text) async {
    if (_socket == null) {
      return Result.failure(
        AppException.unexpected('Voice session is not connected.'),
      );
    }

    await _sendJson({
      'type': 'input.text',
      'payload': {'text': text},
    });
    return const Result.success(null);
  }

  Future<Result<void>> sendOcrContext(String text) async {
    if (_socket == null) {
      return Result.failure(
        AppException.unexpected('Voice session is not connected.'),
      );
    }

    await _sendJson({
      'type': 'input.ocr_context',
      'payload': {'text': text},
    });
    return const Result.success(null);
  }

  Future<Result<void>> sendAudioChunk(Uint8List audioBytes) async {
    if (_socket == null) {
      return Result.failure(
        AppException.unexpected('Voice session is not connected.'),
      );
    }

    await _sendJson({
      'type': 'input.audio',
      'payload': {'audioBase64': base64Encode(audioBytes)},
    });
    return const Result.success(null);
  }

  Future<Result<void>> endInput() async {
    if (_socket == null) {
      return Result.failure(
        AppException.unexpected('Voice session is not connected.'),
      );
    }

    await _sendJson({'type': 'input.end'});
    return const Result.success(null);
  }

  Future<void> close() async {
    try {
      await _sendJson({'type': 'session.cancel'});
    } catch (_) {}

    await _socketSubscription?.cancel();
    _socketSubscription = null;
    await _socket?.close();
    _socket = null;
    _activeSessionId = null;
  }

  Future<void> _sendJson(Map<String, dynamic> payload) async {
    final socket = _socket;
    if (socket == null) {
      throw StateError('Voice session is not connected.');
    }
    await socket.add(jsonEncode(payload));
  }

  void _handleSocketData(dynamic data) {
    try {
      final raw = switch (data) {
        String value => value,
        List<int> value => utf8.decode(value),
        _ => throw const FormatException('Unsupported websocket payload type.'),
      };
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final event = VoiceServerEvent.fromJson(decoded);
      if (event.sessionId != null) {
        _activeSessionId = event.sessionId;
      }
      _eventsController.add(event);
    } catch (e, st) {
      AppLogger.error(
        'Failed to parse voice gateway event',
        error: e,
        stackTrace: st,
        tag: 'VoiceSessionService',
      );
      _eventsController.add(
        const VoiceServerEvent(
          type: 'error',
          message: 'Invalid event received from voice gateway.',
        ),
      );
    }
  }

  void _handleSocketError(Object error, StackTrace stackTrace) {
    AppLogger.error(
      'Voice gateway socket error',
      error: error,
      stackTrace: stackTrace,
      tag: 'VoiceSessionService',
    );
    _eventsController.add(
      VoiceServerEvent(
        type: 'error',
        message: error.toString(),
      ),
    );
  }

  void _handleSocketDone() {
    AppLogger.info('Voice gateway socket closed', tag: 'VoiceSessionService');
    _eventsController.add(const VoiceServerEvent(type: 'session.ended'));
    _socket = null;
    _activeSessionId = null;
  }

  Future<void> dispose() async {
    await close();
    await _eventsController.close();
  }
}
