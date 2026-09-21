import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketService {
  WebSocketService({
    required String baseUrl,
    Duration reconnectDelay = const Duration(seconds: 2),
  }) : _baseUri = Uri.parse(baseUrl),
       _reconnectDelay = reconnectDelay;

  final Uri _baseUri;
  final Duration _reconnectDelay;
  final StreamController<WebSocketEvent> _events =
      StreamController<WebSocketEvent>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  String? _roomId;
  String? _token;
  bool _manualClose = false;

  Stream<WebSocketEvent> get events => _events.stream;

  Future<void> connect({required String roomId, required String token}) async {
    _roomId = roomId;
    _token = token;
    _manualClose = false;

    await _open();
  }

  Future<void> disconnect() async {
    _manualClose = true;
    _reconnectTimer?.cancel();
    await _subscription?.cancel();
    await _channel?.sink.close();
    _subscription = null;
    _channel = null;
  }

  Future<void> dispose() async {
    await disconnect();
    await _events.close();
  }

  Future<void> _open() async {
    final roomId = _roomId;
    final token = _token;

    if (roomId == null || token == null) {
      throw StateError('roomId and token are required before connecting.');
    }

    await _subscription?.cancel();
    await _channel?.sink.close();

    final uri = _baseUri.replace(
      queryParameters: {..._baseUri.queryParameters, 'room_id': roomId},
    );

    _channel = IOWebSocketChannel.connect(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );

    _subscription = _channel!.stream.listen(
      _handleMessage,
      onError: _handleError,
      onDone: _handleDone,
      cancelOnError: false,
    );
  }

  void _handleMessage(dynamic message) {
    try {
      final decoded = message is String ? jsonDecode(message) : message;
      _events.add(WebSocketEvent.fromJson(decoded));
    } on Object catch (error, stackTrace) {
      _events.addError(error, stackTrace);
    }
  }

  void _handleError(Object error, StackTrace stackTrace) {
    _events.addError(error, stackTrace);
    _scheduleReconnect();
  }

  void _handleDone() {
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_manualClose || _reconnectTimer?.isActive == true) {
      return;
    }

    _reconnectTimer = Timer(_reconnectDelay, () {
      _open().catchError((Object error, StackTrace stackTrace) {
        _events.addError(error, stackTrace);
        _scheduleReconnect();
      });
    });
  }
}

class WebSocketEvent {
  const WebSocketEvent({required this.event, this.payload, this.raw});

  final String event;
  final Object? payload;
  final Object? raw;

  factory WebSocketEvent.fromJson(Object? json) {
    if (json is Map<String, dynamic>) {
      return WebSocketEvent(
        event: (json['event'] ?? json['Event'] ?? 'unknown').toString(),
        payload: json['payload'] ?? json['Payload'],
        raw: json,
      );
    }

    return WebSocketEvent(event: 'message', payload: json, raw: json);
  }
}
