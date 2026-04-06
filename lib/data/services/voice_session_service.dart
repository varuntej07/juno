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

const _tag = 'VoiceSession';

class VoiceSessionService {
  final Future<String?> Function() _tokenProvider;

  PlatformWebSocket? _socket;
  final StreamController<VoiceServerEvent> _eventsController =
      StreamController<VoiceServerEvent>.broadcast();
  StreamSubscription<dynamic>? _socketSubscription;
  String? _activeSessionId;

  // Counters for observability
  int _msgSent = 0;
  int _msgReceived = 0;
  int _audioChunksSent = 0;

  VoiceSessionService({
    required Future<String?> Function() tokenProvider,
  }) : _tokenProvider = tokenProvider;

  Stream<VoiceServerEvent> get events => _eventsController.stream;
  bool get isConnected => _socket != null;
  String? get activeSessionId => _activeSessionId;

  Future<Result<void>> startSession(VoiceSessionConfig config) async {
    if (_socket != null) {
      AppLogger.warning(
        'startSession called but socket already exists — returning early',
        tag: _tag,
        metadata: {'userId': config.userId, 'sessionId': _activeSessionId},
      );
      return const Result.success(null);
    }

    final wsUrl = ApiEndpoints.voiceStream;
    AppLogger.info(
      'Connecting to voice gateway',
      tag: _tag,
      metadata: {
        'url': wsUrl,
        'userId': config.userId,
        'voiceId': config.voiceId,
      },
    );

    try {
      final token = await _tokenProvider();
      AppLogger.debug(
        'Token acquired for WS connection',
        tag: _tag,
        metadata: {'hasToken': token != null},
      );

      final headers = <String, dynamic>{
        'x-juno-user-id': config.userId,
        if (token != null) 'Authorization': 'Bearer $token',
      };

      AppLogger.debug(
        'Opening WebSocket',
        tag: _tag,
        metadata: {'url': wsUrl, 'headers': headers.keys.join(', ')},
      );

      final socket = await connectPlatformWebSocket(
        wsUrl,
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

      AppLogger.info(
        'WebSocket connected — sending session.start',
        tag: _tag,
        metadata: {'userId': config.userId},
      );

      await _sendJson({
        'type': 'session.start',
        'payload': config.toJson(),
      });

      return const Result.success(null);
    } catch (e, st) {
      AppLogger.error(
        'Failed to connect to voice gateway',
        error: e,
        stackTrace: st,
        tag: _tag,
        metadata: {'url': wsUrl, 'userId': config.userId},
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
      AppLogger.warning(
        'sendTextInput called but socket is null',
        tag: _tag,
        metadata: {'textPreview': text.length > 40 ? '${text.substring(0, 40)}…' : text},
      );
      return Result.failure(
        AppException.unexpected('Voice session is not connected.'),
      );
    }

    AppLogger.info(
      '→ input.text',
      tag: _tag,
      metadata: {
        'sessionId': _activeSessionId,
        'textLen': text.length,
        'textPreview': text.length > 60 ? '${text.substring(0, 60)}…' : text,
      },
    );
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

    AppLogger.debug('→ input.ocr_context', tag: _tag,
        metadata: {'sessionId': _activeSessionId, 'textLen': text.length});
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

    _audioChunksSent++;
    // Only log every 50 chunks to avoid flooding
    if (_audioChunksSent % 50 == 1) {
      AppLogger.debug(
        '→ input.audio',
        tag: _tag,
        metadata: {
          'sessionId': _activeSessionId,
          'chunkBytes': audioBytes.length,
          'totalChunks': _audioChunksSent,
        },
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

    AppLogger.info(
      '→ input.end',
      tag: _tag,
      metadata: {
        'sessionId': _activeSessionId,
        'audioChunksSent': _audioChunksSent,
        'msgSent': _msgSent,
      },
    );
    await _sendJson({'type': 'input.end'});
    return const Result.success(null);
  }

  Future<void> close() async {
    AppLogger.info(
      'Closing voice session',
      tag: _tag,
      metadata: {
        'sessionId': _activeSessionId,
        'msgSent': _msgSent,
        'msgReceived': _msgReceived,
      },
    );
    try {
      await _sendJson({'type': 'session.cancel'});
    } catch (_) {}

    await _socketSubscription?.cancel();
    _socketSubscription = null;
    await _socket?.close();
    _socket = null;
    _activeSessionId = null;
    _msgSent = 0;
    _msgReceived = 0;
    _audioChunksSent = 0;
  }

  Future<void> _sendJson(Map<String, dynamic> payload) async {
    final socket = _socket;
    if (socket == null) {
      throw StateError('Voice session is not connected.');
    }
    _msgSent++;
    await socket.add(jsonEncode(payload));
  }

  void _handleSocketData(dynamic data) {
    _msgReceived++;
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

      // Log every server event type (skip noisy audio chunks)
      if (event.type != 'assistant.audio.chunk') {
        AppLogger.debug(
          '← ${event.type}',
          tag: _tag,
          metadata: {
            'sessionId': event.sessionId,
            if (event.message != null) 'message': event.message,
            if (event.text != null) 'textPreview': (event.text!.length > 60
                ? '${event.text!.substring(0, 60)}…'
                : event.text),
          },
        );
      }

      // Always log errors at warning level
      if (event.type == 'error') {
        AppLogger.warning(
          '← error event from server',
          tag: _tag,
          metadata: {
            'sessionId': event.sessionId,
            'message': event.message,
          },
        );
      }

      _eventsController.add(event);
    } catch (e, st) {
      AppLogger.error(
        'Failed to parse voice gateway event',
        error: e,
        stackTrace: st,
        tag: _tag,
        metadata: {'rawPreview': data.toString().substring(0, 120.clamp(0, data.toString().length))},
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
      'WebSocket error',
      error: error,
      stackTrace: stackTrace,
      tag: _tag,
      metadata: {
        'sessionId': _activeSessionId,
        'msgSent': _msgSent,
        'msgReceived': _msgReceived,
      },
    );
    _eventsController.add(
      VoiceServerEvent(
        type: 'error',
        message: error.toString(),
      ),
    );
  }

  void _handleSocketDone() {
    AppLogger.info(
      'WebSocket closed by server',
      tag: _tag,
      metadata: {
        'sessionId': _activeSessionId,
        'msgSent': _msgSent,
        'msgReceived': _msgReceived,
        'audioChunksSent': _audioChunksSent,
      },
    );
    _eventsController.add(const VoiceServerEvent(type: 'session.ended'));
    _socket = null;
    _activeSessionId = null;
  }

  Future<void> dispose() async {
    await close();
    await _eventsController.close();
  }
}
