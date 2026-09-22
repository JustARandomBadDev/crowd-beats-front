import 'dart:async';

import 'package:crowd_beats_front/core/websocket/websocket_service.dart';

class SocketRequest {
  const SocketRequest({required this.roomId, required this.token});

  final String roomId;
  final String token;
}

class FakeWebSocketTransport implements WebSocketTransport {
  final List<SocketRequest> requests = [];
  final List<FakeRoomWebSocketConnection> connections = [];
  final List<Object> connectFailures = [];

  @override
  Future<RoomWebSocketConnection> connect({
    required String roomId,
    required String token,
  }) async {
    requests.add(SocketRequest(roomId: roomId, token: token));
    if (connectFailures.isNotEmpty) throw connectFailures.removeAt(0);
    final connection = FakeRoomWebSocketConnection();
    connections.add(connection);
    return connection;
  }
}

class FakeRoomWebSocketConnection implements RoomWebSocketConnection {
  final StreamController<Object?> _messages = StreamController<Object?>();
  bool closed = false;

  @override
  Stream<Object?> get messages => _messages.stream;

  void emit(Object? event) {
    if (!closed) _messages.add(event);
  }

  void emitError(Object error) {
    if (!closed) _messages.addError(error);
  }

  Future<void> disconnect() async {
    if (closed) return;
    closed = true;
    await _messages.close();
  }

  @override
  Future<void> close() => disconnect();
}
