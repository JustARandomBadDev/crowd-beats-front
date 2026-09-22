import 'dart:io';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

abstract interface class WebSocketTransport {
  Future<RoomWebSocketConnection> connect({
    required String roomId,
    required String token,
  });
}

abstract interface class RoomWebSocketConnection {
  Stream<Object?> get messages;

  Future<void> close();
}

class WebSocketService implements WebSocketTransport {
  WebSocketService({
    required String baseUrl,
    this.connectTimeout = const Duration(seconds: 15),
  }) : _baseUri = Uri.parse(baseUrl);

  final Uri _baseUri;
  final Duration connectTimeout;

  @override
  Future<RoomWebSocketConnection> connect({
    required String roomId,
    required String token,
  }) async {
    final uri = _baseUri.replace(
      queryParameters: {..._baseUri.queryParameters, 'room_id': roomId},
    );
    final channel = IOWebSocketChannel.connect(
      uri,
      headers: {'Authorization': 'Bearer $token'},
      connectTimeout: connectTimeout,
    );
    try {
      await channel.ready;
      return _ChannelConnection(channel);
    } on Object catch (error) {
      await channel.sink.close();
      throw WebSocketConnectFailure(
        statusCode: _handshakeStatus(error),
        cause: error,
      );
    }
  }
}

class WebSocketConnectFailure implements Exception {
  const WebSocketConnectFailure({required this.statusCode, this.cause});

  final int? statusCode;
  final Object? cause;

  bool get isInvalidSession => statusCode == HttpStatus.unauthorized;
}

class _ChannelConnection implements RoomWebSocketConnection {
  const _ChannelConnection(this._channel);

  final WebSocketChannel _channel;

  @override
  Stream<Object?> get messages => _channel.stream;

  @override
  Future<void> close() => _channel.sink.close();
}

int? _handshakeStatus(Object error) {
  final inner = error is WebSocketChannelException ? error.inner : error;
  return inner is WebSocketException ? inner.httpStatusCode : null;
}
