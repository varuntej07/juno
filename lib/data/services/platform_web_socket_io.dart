import 'dart:async';
import 'dart:io';

abstract class PlatformWebSocket {
  Stream<dynamic> get stream;

  Future<void> add(String payload);

  Future<void> close([int? code, String? reason]);
}

class IoPlatformWebSocket implements PlatformWebSocket {
  final WebSocket _socket;

  IoPlatformWebSocket(this._socket);

  @override
  Stream<dynamic> get stream => _socket;

  @override
  Future<void> add(String payload) async {
    _socket.add(payload);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    await _socket.close(code, reason);
  }
}

Future<PlatformWebSocket> connectPlatformWebSocket(
  String url, {
  Map<String, dynamic>? headers,
  Duration? pingInterval,
}) async {
  final socket = await WebSocket.connect(
    url,
    headers: headers,
  );
  if (pingInterval != null) {
    socket.pingInterval = pingInterval;
  }
  return IoPlatformWebSocket(socket);
}
