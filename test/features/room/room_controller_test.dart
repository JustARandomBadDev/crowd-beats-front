import 'dart:async';

import 'package:crowd_beats_front/core/api/api_client.dart';
import 'package:crowd_beats_front/core/api/crowd_beats_api.dart';
import 'package:crowd_beats_front/core/config/app_providers.dart';
import 'package:crowd_beats_front/core/storage/session_storage.dart';
import 'package:crowd_beats_front/core/websocket/websocket_service.dart';
import 'package:crowd_beats_front/features/room/room_controller.dart';
import 'package:crowd_beats_front/features/session/session_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../fixtures.dart';
import '../../websocket_fakes.dart';

const roomAId = '11111111-1111-4111-8111-111111111111';
const roomBId = '22222222-2222-4222-8222-222222222222';

class MemoryStorage extends SessionStorage {
  MemoryStorage(this.token);

  String? token;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> saveToken(String value) async => token = value;

  @override
  Future<void> clearSession() async => token = null;
}

class ControllerHarness {
  ControllerHarness(
    Future<http.Response> Function(http.Request) handler, {
    Duration reconnectDelay = Duration.zero,
    MemoryStorage? storage,
  }) : sockets = FakeWebSocketTransport(),
       storage = storage ?? MemoryStorage('token-a') {
    client = ApiClient(
      baseUrl: 'http://localhost:8080',
      httpClient: MockClient(handler),
    );
    container = ProviderContainer(
      overrides: [
        sessionStorageProvider.overrideWithValue(this.storage),
        crowdBeatsApiProvider.overrideWithValue(CrowdBeatsApi(client)),
        webSocketServiceProvider.overrideWithValue(sockets),
        roomReconnectDelayProvider.overrideWithValue((_) => reconnectDelay),
      ],
    );
  }

  final FakeWebSocketTransport sockets;
  final MemoryStorage storage;
  late final ApiClient client;
  late final ProviderContainer container;

  void dispose() {
    container.dispose();
    client.close();
  }
}

Map<String, dynamic> room(String id, String name) => {
  ...roomJson,
  'id': id,
  'name': name,
};

Map<String, dynamic> track(String id, String title) => {
  ...spotifyTrackJson,
  'spotify_track_id': id,
  'title': title,
};

Map<String, dynamic> item(int position, String id, String title) => {
  'position': position,
  'room_track_id': 'room-track-$id',
  'score': 10 - position,
  'vote_count': 10 - position,
  'track': track(id, title),
  'proposed_by': null,
};

Map<String, dynamic> queueAt(
  String timestamp, {
  List<Map<String, dynamic>> items = const [],
  Map<String, dynamic>? nowPlaying,
}) => {'items': items, 'now_playing': nowPlaying, 'updated_at': timestamp};

Map<String, dynamic> event(
  String name,
  Object payload, {
  String roomId = roomAId,
}) => {
  'event': name,
  'room_id': roomId,
  'timestamp': '2026-09-21T09:00:00Z',
  'payload': payload,
};

Future<void> flushEvents([int count = 12]) async {
  for (var i = 0; i < count; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

ProviderSubscription<RoomState> listenToRoom(
  ProviderContainer container,
  RoomSessionKey key,
) {
  return container.listen(
    roomControllerProvider(key),
    (_, _) {},
    fireImmediately: true,
  );
}

void main() {
  test(
    'initial REST state starts the correctly authenticated socket',
    () async {
      final harness = ControllerHarness((request) async {
        if (request.url.path == '/api/v1/rooms/$roomAId') {
          return apiResponse(room(roomAId, 'Room A'));
        }
        if (request.url.path == '/api/v1/rooms/$roomAId/queue') {
          return apiResponse(queueAt('2026-09-21T08:00:00Z'));
        }
        throw StateError('Unexpected request ${request.url.path}');
      });
      addTearDown(harness.dispose);
      const key = RoomSessionKey(roomId: roomAId, token: 'token-a');
      final subscription = listenToRoom(harness.container, key);

      await flushEvents();
      expect(
        harness.container.read(roomControllerProvider(key)).hasData,
        isTrue,
      );
      expect(harness.sockets.requests, hasLength(1));
      expect(harness.sockets.requests.single.roomId, roomAId);
      expect(harness.sockets.requests.single.token, 'token-a');

      subscription.close();
      await flushEvents();
      expect(harness.sockets.connections.single.closed, isTrue);
    },
  );

  test(
    'queue_updated replaces the complete snapshot in backend order',
    () async {
      final harness = ControllerHarness((request) async {
        if (request.url.path.endsWith('/queue')) {
          return apiResponse(queueAt('2026-09-21T08:00:00Z'));
        }
        return apiResponse(room(roomAId, 'Room A'));
      });
      addTearDown(harness.dispose);
      const key = RoomSessionKey(roomId: roomAId, token: 'token-a');
      final subscription = listenToRoom(harness.container, key);
      addTearDown(subscription.close);
      await flushEvents();

      harness.sockets.connections.single.emit(
        event(
          'queue_updated',
          queueAt(
            '2026-09-21T08:01:00Z',
            items: [
              item(1, 'second', 'Backend First'),
              item(2, 'first', 'Backend Second'),
            ],
            nowPlaying: {
              'room_track_id': 'playing',
              'vote_count': 5,
              'track': track('playing', 'Now Playing'),
              'proposed_by': 'Sam',
            },
          ),
        ),
      );
      await flushEvents();

      final queue = harness.container.read(roomControllerProvider(key)).queue!;
      expect(queue.items.map((entry) => entry.track.title), [
        'Backend First',
        'Backend Second',
      ]);
      expect(queue.nowPlaying?.track.title, 'Now Playing');
    },
  );

  test(
    'sync_required deduplicates concurrent REST resynchronization',
    () async {
      var queueRequests = 0;
      final pending = Completer<http.Response>();
      final harness = ControllerHarness((request) async {
        if (!request.url.path.endsWith('/queue')) {
          return apiResponse(room(roomAId, 'Room A'));
        }
        queueRequests++;
        if (queueRequests == 1) {
          return apiResponse(queueAt('2026-09-21T08:00:00Z'));
        }
        return pending.future;
      });
      addTearDown(harness.dispose);
      const key = RoomSessionKey(roomId: roomAId, token: 'token-a');
      final subscription = listenToRoom(harness.container, key);
      addTearDown(subscription.close);
      await flushEvents();

      final socket = harness.sockets.connections.single;
      socket.emit(event('sync_required', <String, dynamic>{}));
      socket.emit(event('sync_required', <String, dynamic>{}));
      await flushEvents();
      expect(queueRequests, 2);

      pending.complete(
        apiResponse(
          queueAt(
            '2026-09-21T08:01:00Z',
            items: [item(1, 'synced', 'Synced Track')],
          ),
        ),
      );
      await flushEvents();
      expect(
        harness.container
            .read(roomControllerProvider(key))
            .queue!
            .items
            .single
            .track
            .title,
        'Synced Track',
      );
    },
  );

  test('failed resync retains queue and a later sync recovers', () async {
    var queueRequests = 0;
    final harness = ControllerHarness((request) async {
      if (!request.url.path.endsWith('/queue')) {
        return apiResponse(room(roomAId, 'Room A'));
      }
      queueRequests++;
      if (queueRequests == 1) {
        return apiResponse(
          queueAt(
            '2026-09-21T08:00:00Z',
            items: [item(1, 'old', 'Last Valid Track')],
          ),
        );
      }
      if (queueRequests == 2) return apiError('INTERNAL_ERROR', status: 500);
      return apiResponse(
        queueAt(
          '2026-09-21T08:02:00Z',
          items: [item(1, 'new', 'Recovered Track')],
        ),
      );
    });
    addTearDown(harness.dispose);
    const key = RoomSessionKey(roomId: roomAId, token: 'token-a');
    final subscription = listenToRoom(harness.container, key);
    addTearDown(subscription.close);
    await flushEvents();

    final socket = harness.sockets.connections.single;
    socket.emit(event('sync_required', <String, dynamic>{}));
    await flushEvents();
    var state = harness.container.read(roomControllerProvider(key));
    expect(state.queue!.items.single.track.title, 'Last Valid Track');
    expect(state.liveMessage, contains('failed'));

    socket.emit(event('sync_required', <String, dynamic>{}));
    await flushEvents();
    state = harness.container.read(roomControllerProvider(key));
    expect(state.queue!.items.single.track.title, 'Recovered Track');
    expect(state.liveMessage, isNull);
  });

  test(
    'unexpected disconnect reconnects once and waits for sync_required',
    () async {
      var queueRequests = 0;
      final harness = ControllerHarness((request) async {
        if (request.url.path.endsWith('/queue')) {
          queueRequests++;
          return apiResponse(queueAt('2026-09-21T08:00:00Z'));
        }
        return apiResponse(room(roomAId, 'Room A'));
      });
      addTearDown(harness.dispose);
      const key = RoomSessionKey(roomId: roomAId, token: 'token-a');
      final subscription = listenToRoom(harness.container, key);
      addTearDown(subscription.close);
      await flushEvents();

      await harness.sockets.connections.single.disconnect();
      await flushEvents();
      expect(harness.sockets.requests, hasLength(2));
      expect(harness.sockets.connections, hasLength(2));
      expect(queueRequests, 1);

      harness.sockets.connections.last.emit(
        event('sync_required', <String, dynamic>{}),
      );
      await flushEvents();
      expect(queueRequests, 2);
      expect(
        harness.container.read(roomControllerProvider(key)).connectionStatus,
        LiveConnectionStatus.connected,
      );
    },
  );

  test('room switch closes A and late A data cannot alter B', () async {
    final harness = ControllerHarness((request) async {
      final id = request.url.path.contains(roomBId) ? roomBId : roomAId;
      if (request.url.path.endsWith('/queue')) {
        return apiResponse(
          queueAt(
            '2026-09-21T08:00:00Z',
            items: [item(1, id, id == roomAId ? 'A Track' : 'B Track')],
          ),
        );
      }
      return apiResponse(room(id, id == roomAId ? 'Room A' : 'Room B'));
    });
    addTearDown(harness.dispose);
    const keyA = RoomSessionKey(roomId: roomAId, token: 'token-a');
    const keyB = RoomSessionKey(roomId: roomBId, token: 'token-b');
    final subscriptionA = listenToRoom(harness.container, keyA);
    await flushEvents();
    final oldSocket = harness.sockets.connections.single;

    subscriptionA.close();
    await flushEvents();
    expect(oldSocket.closed, isTrue);

    final subscriptionB = listenToRoom(harness.container, keyB);
    addTearDown(subscriptionB.close);
    await flushEvents();
    oldSocket.emit(
      event(
        'queue_updated',
        queueAt(
          '2026-09-21T09:00:00Z',
          items: [item(1, 'late', 'Late A Track')],
        ),
      ),
    );
    await flushEvents();

    final stateB = harness.container.read(roomControllerProvider(keyB));
    expect(stateB.queue!.items.single.track.title, 'B Track');
    expect(harness.sockets.requests.map((request) => request.roomId), [
      roomAId,
      roomBId,
    ]);
  });

  test('stop closes the socket and cancels pending reconnect work', () async {
    final harness = ControllerHarness(
      (request) async => request.url.path.endsWith('/queue')
          ? apiResponse(queueAt('2026-09-21T08:00:00Z'))
          : apiResponse(room(roomAId, 'Room A')),
      reconnectDelay: const Duration(milliseconds: 30),
    );
    addTearDown(harness.dispose);
    const key = RoomSessionKey(roomId: roomAId, token: 'token-a');
    final subscription = listenToRoom(harness.container, key);
    addTearDown(subscription.close);
    await flushEvents();

    await harness.sockets.connections.single.disconnect();
    await harness.container.read(roomControllerProvider(key).notifier).stop();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(harness.sockets.requests, hasLength(1));
    expect(
      harness.container.read(roomControllerProvider(key)).connectionStatus,
      LiveConnectionStatus.stopped,
    );
  });

  test('unknown and malformed messages do not discard the queue', () async {
    final harness = ControllerHarness((request) async {
      if (request.url.path.endsWith('/queue')) {
        return apiResponse(
          queueAt(
            '2026-09-21T08:00:00Z',
            items: [item(1, 'kept', 'Kept Track')],
          ),
        );
      }
      return apiResponse(room(roomAId, 'Room A'));
    });
    addTearDown(harness.dispose);
    const key = RoomSessionKey(roomId: roomAId, token: 'token-a');
    final subscription = listenToRoom(harness.container, key);
    addTearDown(subscription.close);
    await flushEvents();

    final socket = harness.sockets.connections.single;
    socket.emit(event('future_event', {'future': true}));
    socket.emit(event('queue_updated', {'items': <Object>[]}));
    await flushEvents();

    final state = harness.container.read(roomControllerProvider(key));
    expect(state.queue!.items.single.track.title, 'Kept Track');
    expect(state.liveMessage, contains('invalid'));
  });

  test('newer WebSocket snapshot wins an overlapping REST resync', () async {
    var queueRequests = 0;
    final olderRest = Completer<http.Response>();
    final harness = ControllerHarness((request) async {
      if (!request.url.path.endsWith('/queue')) {
        return apiResponse(room(roomAId, 'Room A'));
      }
      queueRequests++;
      if (queueRequests == 1) {
        return apiResponse(queueAt('2026-09-21T08:00:00Z'));
      }
      return olderRest.future;
    });
    addTearDown(harness.dispose);
    const key = RoomSessionKey(roomId: roomAId, token: 'token-a');
    final subscription = listenToRoom(harness.container, key);
    addTearDown(subscription.close);
    await flushEvents();
    final socket = harness.sockets.connections.single;

    socket.emit(event('sync_required', <String, dynamic>{}));
    await flushEvents();
    socket.emit(
      event(
        'queue_updated',
        queueAt(
          '2026-09-21T08:03:00Z',
          items: [item(1, 'newer', 'Newer WebSocket Track')],
        ),
      ),
    );
    olderRest.complete(
      apiResponse(
        queueAt(
          '2026-09-21T08:02:00Z',
          items: [item(1, 'older', 'Older REST Track')],
        ),
      ),
    );
    await flushEvents();

    var state = harness.container.read(roomControllerProvider(key));
    expect(state.queue!.items.single.track.title, 'Newer WebSocket Track');

    socket.emit(
      event(
        'queue_updated',
        queueAt(
          '2026-09-21T08:04:00Z',
          items: [item(1, 'newest', 'Newest Track')],
        ),
      ),
    );
    await flushEvents();
    state = harness.container.read(roomControllerProvider(key));
    expect(state.queue!.items.single.track.title, 'Newest Track');
  });

  test(
    'authoritative handshake 401 invalidates the matching session',
    () async {
      final storage = MemoryStorage('token-a');
      final harness = ControllerHarness((request) async {
        if (request.url.path == '/api/v1/sessions/me') {
          return apiResponse({
            'session': {
              'id': 'session-a',
              'room_id': roomAId,
              'nickname': 'Camille',
              'role': 'guest',
              'status': 'active',
              'last_seen_at': '2026-09-21T08:00:00Z',
            },
          });
        }
        if (request.url.path.endsWith('/queue')) {
          return apiResponse(queueAt('2026-09-21T08:00:00Z'));
        }
        return apiResponse(room(roomAId, 'Room A'));
      }, storage: storage);
      harness.sockets.connectFailures.add(
        const WebSocketConnectFailure(statusCode: 401),
      );
      addTearDown(harness.dispose);
      await harness.container
          .read(sessionControllerProvider.notifier)
          .bootstrap();
      const key = RoomSessionKey(roomId: roomAId, token: 'token-a');
      final subscription = listenToRoom(harness.container, key);
      addTearDown(subscription.close);
      await flushEvents();

      expect(storage.token, isNull);
      expect(
        harness.container.read(sessionControllerProvider).phase,
        SessionPhase.invalid,
      );
    },
  );
}
