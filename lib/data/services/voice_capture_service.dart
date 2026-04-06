import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/logging/app_logger.dart';

abstract class VoiceCaptureService {
  bool get isSupported;
  Future<void> start(void Function(Uint8List audioBytes) onAudioChunk);
  Future<void> stop();
}

/// Streams 16kHz, 16-bit, mono PCM chunks directly to the callback.
/// Each chunk is forwarded to the voice gateway via VoiceSessionService.
class FlutterSoundCaptureService implements VoiceCaptureService {
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();

  StreamController<Uint8List>? _audioController;
  StreamSubscription<Uint8List>? _audioSubscription;
  bool _isOpen = false;

  @override
  bool get isSupported => true;

  @override
  Future<void> start(void Function(Uint8List audioBytes) onAudioChunk) async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      AppLogger.error(
        'Microphone permission denied — cannot start voice capture',
        tag: 'VoiceCaptureService',
      );
      return;
    }

    if (!_isOpen) {
      await _recorder.openRecorder();
      _isOpen = true;
    }

    _audioController = StreamController<Uint8List>();
    _audioSubscription = _audioController!.stream.listen((bytes) {
      if (bytes.isNotEmpty) onAudioChunk(bytes);
    });

    await _recorder.startRecorder(
      codec: Codec.pcm16,
      sampleRate: 16000,
      numChannels: 1,
      toStream: _audioController!.sink,
    );

    AppLogger.info('Voice capture started', tag: 'VoiceCaptureService');
  }

  @override
  Future<void> stop() async {
    try {
      if (_recorder.isRecording) {
        await _recorder.stopRecorder();
      }
      await _audioSubscription?.cancel();
      _audioSubscription = null;
      await _audioController?.close();
      _audioController = null;
      AppLogger.info('Voice capture stopped', tag: 'VoiceCaptureService');
    } catch (e, st) {
      AppLogger.error(
        'Error stopping voice capture',
        error: e,
        stackTrace: st,
        tag: 'VoiceCaptureService',
      );
    }
  }
}
