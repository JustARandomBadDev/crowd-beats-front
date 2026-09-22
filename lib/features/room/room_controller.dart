import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/crowd_beats_api.dart';
import '../../core/config/app_providers.dart';
import '../../core/websocket/room_event.dart';
import '../../core/websocket/websocket_service.dart';
import '../../models/queue.dart';
import '../../models/room.dart';
import '../session/session_controller.dart';

class RoomSessionKey {
  const RoomSessionKey({required this.roomId, required this.token});

  final String roomId;
  final String token;

  @override
  bool operator ==(Object other) =>
      other is RoomSessionKey && other.roomId == roomId && other.token == token;

  @override
  int get hashCode => Object.hash(roomId, token);
}

enum LiveConnectionStatus { connecting, connected, reconnecting, stopped }

class RoomState {
  const RoomState({
    this.room,
    this.queue,
    this.initialLoading = true,
    this.initialError,
    this.connectionStatus = LiveConnectionStatus.connecting,
    this.synchronizing = false,
    this.liveMessage,
  });

  final RoomDto? room;
  final QueueSnapshotDto? queue;
  final bool initialLoading;
  final Object? initialError;
  final LiveConnectionStatus connectionStatus;
  final bool synchronizing;
  final String? liveMessage;

  bool get hasData => room != null && queue != null;

  RoomState copyWith({
    Object? room = _unchanged,
    Object? queue = _unchanged,
    bool? initialLoading,
    Object? initialError = _unchanged,
    LiveConnectionStatus? connectionStatus,
    bool? synchronizing,
    Object? liveMessage = _unchanged,
  }) {
    return RoomState(
      room: identical(room, _unchanged) ? this.room : room as RoomDto?,
      queue: identical(queue, _unchanged)
          ? this.queue
          : queue as QueueSnapshotDto?,
      initialLoading: initialLoading ?? this.initialLoading,
      initialError: identical(initialError, _unchanged)
          ? this.initialError
          : initialError,
      connectionStatus: connectionStatus ?? this.connectionStatus,
      synchronizing: synchronizing ?? this.synchronizing,
      liveMessage: identical(liveMessage, _unchanged)
          ? this.liveMessage
          : liveMessage as String?,
    );
  }
}

const _unchanged = Object();

final roomControllerProvider = NotifierProvider.autoDispose
    .family<RoomController, RoomState, RoomSessionKey>(RoomController.new);

class RoomController extends Notifier<RoomState> {
  RoomController(this.key);

  final RoomSessionKey key;

  late CrowdBeatsApi _api;
  late WebSocketTransport _transport;
  late Duration Function(int) _reconnectDelay;
  RoomWebSocketConnection? _connection;
  StreamSubscription<Object?>? _subscription;
  Timer? _reconnectTimer;
  Future<void>? _initialRequest;
  Future<void>? _resyncRequest;
  bool _connecting = false;
  bool _stopped = false;
  bool _disposed = false;
  int _connectionGeneration = 0;
  int _reconnectAttempt = 0;

  @override
  RoomState build() {
    _api = ref.read(crowdBeatsApiProvider);
    _transport = ref.read(webSocketServiceProvider);
    _reconnectDelay = ref.read(roomReconnectDelayProvider);
    ref.onDispose(() {
      _disposed = true;
      _stopped = true;
      _reconnectTimer?.cancel();
      unawaited(_closeConnection());
    });
    Future.microtask(loadInitial);
    return const RoomState();
  }

  Future<void> loadInitial() {
    final current = _initialRequest;
    if (current != null) return current;
    final request = _loadRoomAndQueue();
    _initialRequest = request;
    return request.whenComplete(() {
      if (identical(_initialRequest, request)) _initialRequest = null;
    });
  }

  Future<void> refresh() => loadInitial();

  Future<void> _loadRoomAndQueue() async {
    final hadData = state.hasData;
    if (!hadData) {
      state = state.copyWith(initialLoading: true, initialError: null);
    }
    try {
      final roomResponse = await _api.getRoom(key.roomId);
      final queueResponse = await _api.getQueue(key.roomId);
      if (_disposed) return;
      final queue = _newest(queueResponse.data, state.queue);
      state = state.copyWith(
        room: roomResponse.data,
        queue: queue,
        initialLoading: false,
        initialError: null,
        liveMessage: null,
      );
      if (!_stopped && _connection == null && !_connecting) {
        unawaited(_connect());
      }
    } on Object catch (error) {
      if (_disposed) return;
      if (hadData) {
        state = state.copyWith(
          initialLoading: false,
          liveMessage: 'Could not refresh the room. Showing saved live state.',
        );
      } else {
        state = state.copyWith(initialLoading: false, initialError: error);
      }
    }
  }

  Future<void> resynchronizeQueue() {
    final current = _resyncRequest;
    if (current != null) return current;
    final request = _resynchronizeQueue();
    _resyncRequest = request;
    return request.whenComplete(() {
      if (identical(_resyncRequest, request)) _resyncRequest = null;
    });
  }

  Future<void> _resynchronizeQueue() async {
    if (_disposed || state.queue == null) return;
    state = state.copyWith(synchronizing: true, liveMessage: null);
    try {
      final response = await _api.getQueue(key.roomId);
      if (_disposed) return;
      state = state.copyWith(
        queue: _newest(response.data, state.queue),
        synchronizing: false,
        liveMessage: null,
      );
    } on Object {
      if (_disposed) return;
      state = state.copyWith(
        synchronizing: false,
        liveMessage: 'Live synchronization failed. The last queue is shown.',
      );
    }
  }

  Future<void> stop() async {
    _stopped = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    if (!_disposed) {
      state = state.copyWith(connectionStatus: LiveConnectionStatus.stopped);
    }
    await _closeConnection();
  }

  void resume() {
    if (_disposed || !_stopped || !state.hasData) return;
    _stopped = false;
    unawaited(_connect());
  }

  Future<void> _connect() async {
    if (_disposed || _stopped || _connecting || _connection != null) return;
    _connecting = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final generation = ++_connectionGeneration;
    state = state.copyWith(
      connectionStatus: _reconnectAttempt == 0
          ? LiveConnectionStatus.connecting
          : LiveConnectionStatus.reconnecting,
    );
    try {
      final connection = await _transport.connect(
        roomId: key.roomId,
        token: key.token,
      );
      if (_disposed || _stopped || generation != _connectionGeneration) {
        await connection.close();
        return;
      }
      _connection = connection;
      _reconnectAttempt = 0;
      _subscription = connection.messages.listen(
        (message) => _handleMessage(message, generation),
        onError: (Object error, StackTrace stackTrace) {
          _handleConnectionLoss(generation);
        },
        onDone: () => _handleConnectionLoss(generation),
        cancelOnError: false,
      );
      state = state.copyWith(
        connectionStatus: LiveConnectionStatus.connected,
        liveMessage: null,
      );
    } on WebSocketConnectFailure catch (failure) {
      if (_disposed || _stopped || generation != _connectionGeneration) return;
      if (failure.isInvalidSession) {
        _stopped = true;
        state = state.copyWith(connectionStatus: LiveConnectionStatus.stopped);
        await ref
            .read(sessionControllerProvider.notifier)
            .invalidateFromServer(token: key.token);
      } else {
        _scheduleReconnect();
      }
    } on Object {
      if (_disposed || _stopped || generation != _connectionGeneration) return;
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  void _handleMessage(Object? message, int generation) {
    if (_disposed || _stopped || generation != _connectionGeneration) return;
    try {
      final event = RoomEvent.parse(message);
      if (event.roomId != key.roomId) return;
      switch (event) {
        case SyncRequiredEvent():
          unawaited(resynchronizeQueue());
        case QueueUpdatedEvent(:final snapshot):
          state = state.copyWith(
            queue: _newest(snapshot, state.queue),
            liveMessage: null,
          );
        case InformationalRoomEvent():
        case UnknownRoomEvent():
          break;
      }
    } on Object {
      state = state.copyWith(
        liveMessage: 'A live update was invalid. The last queue is shown.',
      );
    }
  }

  void _handleConnectionLoss(int generation) {
    if (_disposed || _stopped || generation != _connectionGeneration) return;
    _connectionGeneration++;
    final connection = _connection;
    final subscription = _subscription;
    _connection = null;
    _subscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    if (connection != null) unawaited(connection.close());
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || _stopped || _reconnectTimer?.isActive == true) return;
    _reconnectAttempt++;
    state = state.copyWith(
      connectionStatus: LiveConnectionStatus.reconnecting,
      liveMessage: 'Live updates unavailable. Reconnecting…',
    );
    _reconnectTimer = Timer(_reconnectDelay(_reconnectAttempt), () {
      _reconnectTimer = null;
      unawaited(_connect());
    });
  }

  Future<void> _closeConnection() async {
    _connectionGeneration++;
    final subscription = _subscription;
    final connection = _connection;
    _subscription = null;
    _connection = null;
    await subscription?.cancel();
    await connection?.close();
  }
}

QueueSnapshotDto _newest(QueueSnapshotDto incoming, QueueSnapshotDto? current) {
  if (current == null) return incoming;
  final incomingAt = incoming.updatedAt;
  final currentAt = current.updatedAt;
  if (incomingAt != null &&
      currentAt != null &&
      incomingAt.isBefore(currentAt)) {
    return current;
  }
  return incoming;
}
