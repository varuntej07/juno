import 'dart:async';

abstract class PlatformWebSocket {
  Stream<dynamic> get stream;

  Future<void> add(String payload);

  Future<void> close([int? code, String? reason]);
}

Future<PlatformWebSocket> connectPlatformWebSocket(
  String url, {
  Map<String, dynamic>? headers,
  Duration? pingInterval,
}) {
  throw UnsupportedError('Realtime voice sessions are not supported on this platform.');
}
