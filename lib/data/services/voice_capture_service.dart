import 'dart:typed_data';

abstract class VoiceCaptureService {
  bool get isSupported;

  Future<void> start(void Function(Uint8List audioBytes) onAudioChunk);

  Future<void> stop();
}

class NoopVoiceCaptureService implements VoiceCaptureService {
  @override
  bool get isSupported => false;

  @override
  Future<void> start(void Function(Uint8List audioBytes) onAudioChunk) async {}

  @override
  Future<void> stop() async {}
}
