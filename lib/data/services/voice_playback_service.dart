import 'dart:convert';
import 'dart:typed_data';

import '../../core/logging/app_logger.dart';

abstract class VoicePlaybackService {
  Future<void> enqueueAudio({
    required String audioBase64,
    required String mimeType,
    int? sampleRateHertz,
  });
}

class NoopVoicePlaybackService implements VoicePlaybackService {
  @override
  Future<void> enqueueAudio({
    required String audioBase64,
    required String mimeType,
    int? sampleRateHertz,
  }) async {
    if (audioBase64.isEmpty) return;

    final bytes = base64Decode(audioBase64);
    AppLogger.info(
      'Discarding streamed audio chunk in noop playback service',
      tag: 'VoicePlaybackService',
      metadata: <String, dynamic>{
        'mimeType': mimeType,
        'sampleRateHertz': sampleRateHertz,
        'bytes': Uint8List.fromList(bytes).length,
      },
    );
  }
}
