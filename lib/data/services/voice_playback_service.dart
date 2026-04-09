import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_sound/flutter_sound.dart';

import '../../core/logging/app_logger.dart';

abstract class VoicePlaybackService {
  Future<void> enqueueAudio({
    required String audioBase64,
    required String mimeType,
    int? sampleRateHertz,
  });

  Future<void> dispose();
}

/// Plays Nova Sonic PCM audio chunks in real-time using flutter_sound's
/// streaming mode. Chunks are fed as they arrive — no buffering wait.
class FlutterSoundPlaybackService implements VoicePlaybackService {
  final FlutterSoundPlayer _player = FlutterSoundPlayer();

  bool _isOpen = false;
  bool _isPlaying = false;

  // Buffer chunks that arrive before the player stream is open.
  final List<Uint8List> _pendingChunks = [];

  Future<void> _ensureOpen(int sampleRate) async {
    if (!_isOpen) {
      await _player.openPlayer();
      _isOpen = true;
    }
    if (!_isPlaying) {
      await _player.startPlayerFromStream(
        codec: Codec.pcm16,
        numChannels: 1,
        sampleRate: sampleRate,
        bufferSize: 4096,
        interleaved: true,
      );
      _isPlaying = true;

      // Flush any chunks that arrived before the stream was open
      for (final chunk in _pendingChunks) {
        await _player.feedUint8FromStream(chunk);
      }
      _pendingChunks.clear();
    }
  }

  @override
  Future<void> enqueueAudio({
    required String audioBase64,
    required String mimeType,
    int? sampleRateHertz,
  }) async {
    if (audioBase64.isEmpty) return;

    final bytes = Uint8List.fromList(base64Decode(audioBase64));
    final sampleRate = sampleRateHertz ?? 16000;

    try {
      if (!_isPlaying) {
        // Queue while the player is starting up
        _pendingChunks.add(bytes);
        await _ensureOpen(sampleRate);
      } else {
        await _player.feedUint8FromStream(bytes);
      }
    } catch (e, st) {
      AppLogger.error(
        'Error feeding audio chunk to player',
        error: e,
        stackTrace: st,
        tag: 'VoicePlaybackService',
      );
      // Reset state so next session can start fresh
      _isPlaying = false;
    }
  }

  @override
  Future<void> dispose() async {
    try {
      if (_isPlaying) {
        await _player.stopPlayer();
        _isPlaying = false;
      }
      if (_isOpen) {
        await _player.closePlayer();
        _isOpen = false;
      }
    } catch (e, st) {
      AppLogger.error(
        'Error disposing playback service',
        error: e,
        stackTrace: st,
        tag: 'VoicePlaybackService',
      );
    }
  }
}
