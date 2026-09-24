import 'package:crowd_beats_front/core/api/api_client.dart';
import 'package:crowd_beats_front/core/api/crowd_beats_api.dart';
import 'package:crowd_beats_front/core/config/app_providers.dart';
import 'package:crowd_beats_front/core/storage/session_storage.dart';
import 'package:crowd_beats_front/core/theme/app_theme.dart';
import 'package:crowd_beats_front/features/room/room_controller.dart';
import 'package:crowd_beats_front/features/room/room_screen.dart';
import 'package:crowd_beats_front/features/search/track_search_screen.dart';
import 'package:crowd_beats_front/features/session/join_screen.dart';
import 'package:crowd_beats_front/features/session/session_controller.dart';
import 'package:crowd_beats_front/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../fixtures.dart';
import '../../websocket_fakes.dart';

const roomAId = '11111111-1111-4111-8111-111111111111';
const roomBId = '22222222-2222-4222-8222-222222222222';

class MemorySessionStorage extends SessionStorage {
  MemorySessionStorage(this.token);

  String? token;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> saveToken(String value) async => token = value;

  @override
  Future<void> clearSession() async => token = null;
}

class RoomHarness {
  RoomHarness(
    Future<http.Response> Function(http.Request) handler, {
    Duration reconnectDelay = Duration.zero,
  }) : storage = MemorySessionStorage('token-a'),
       sockets = FakeWebSocketTransport() {
    client = ApiClient(
      baseUrl: 'http://localhost:8080',
      httpClient: MockClient(handler),
    );
    container = ProviderContainer(
      overrides: [
        sessionStorageProvider.overrideWithValue(storage),
        crowdBeatsApiProvider.overrideWithValue(CrowdBeatsApi(client)),
        webSocketServiceProvider.overrideWithValue(sockets),
        roomReconnectDelayProvider.overrideWithValue((_) => reconnectDelay),
      ],
    );
  }

  final MemorySessionStorage storage;
  final FakeWebSocketTransport sockets;
  late final ApiClient client;
  late final ProviderContainer container;
  var _disposed = false;

  Future<void> bootstrap() =>
      container.read(sessionControllerProvider.notifier).bootstrap();

  void dispose() {
    if (_disposed) return;
    _disposed = true;
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

Map<String, dynamic> queuedTrack(int position, String id, String title) => {
  'position': position,
  'room_track_id': 'queued-$id',
  'score': 6 - position,
  'vote_count': 6 - position,
  'track': track(id, title),
  'proposed_by': position == 1 ? 'Alex' : null,
};

Map<String, dynamic> queue({
  List<Map<String, dynamic>> items = const [],
  Map<String, dynamic>? nowPlaying,
}) => {
  'items': items,
  'now_playing': nowPlaying,
  'updated_at': '2026-09-21T08:02:00Z',
};

http.Response currentSession(String roomId) => apiResponse({
  'session': {
    'id': 'session-a',
    'room_id': roomId,
    'nickname': 'Camille',
    'role': 'guest',
    'status': 'active',
    'last_seen_at': '2026-09-21T08:01:00Z',
  },
});

http.Response joinedRoomB() => apiResponse({
  'room': room(roomBId, 'Room B'),
  'session': {
    'id': 'session-b',
    'nickname': 'Camille',
    'role': 'guest',
    'token': 'token-b',
  },
  'ws': {'url': '/ws?room_id=$roomBId'},
});

Widget appFor(RoomHarness harness, Widget home) => UncontrolledProviderScope(
  container: harness.container,
  child: MaterialApp(theme: AppTheme.dark, home: home),
);

Future<void> disposeHarness(WidgetTester tester, RoomHarness harness) async {
  await tester.pumpWidget(const SizedBox.shrink());
  harness.dispose();
}

void main() {
  testWidgets('loads room, now playing and queued tracks in backend order', (
    tester,
  ) async {
    final snapshot = queue(
      nowPlaying: {
        'room_track_id': 'playing-id',
        'vote_count': 7,
        'track': track('playing', 'Currently Playing'),
        'proposed_by': 'Sam',
      },
      items: [
        queuedTrack(1, 'first', 'First Track'),
        queuedTrack(2, 'second', 'Second Track'),
      ],
    );
    final harness = RoomHarness((request) async {
      switch (request.url.path) {
        case '/api/v1/sessions/me':
          return currentSession(roomAId);
        case '/api/v1/rooms/$roomAId':
          return apiResponse(room(roomAId, 'Room A'));
        case '/api/v1/rooms/$roomAId/queue':
          return apiResponse(snapshot);
        case '/api/v1/rooms/$roomAId/votes':
          return apiResponse({
            'vote_added': true,
            'room_track_id': 'queued-first',
            'current_vote_count': 6,
            'votes_remaining': 4,
          });
        default:
          throw StateError('Unexpected request ${request.url.path}');
      }
    });
    addTearDown(harness.dispose);
    await harness.bootstrap();

    await tester.pumpWidget(appFor(harness, const RoomScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Room A'), findsWidgets);
    expect(find.text('Now playing'), findsOneWidget);
    expect(find.text('Currently Playing'), findsOneWidget);
    expect(find.text('First Track'), findsOneWidget);
    expect(find.text('Second Track'), findsOneWidget);
    expect(find.byTooltip('Vote for Currently Playing'), findsOneWidget);
    expect(find.byTooltip('Vote for First Track'), findsOneWidget);
    expect(find.byTooltip('Vote for Second Track'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('First Track')).dy,
      lessThan(tester.getTopLeft(find.text('Second Track')).dy),
    );
    final loaded = harness.container.read(
      roomControllerProvider(
        const RoomSessionKey(roomId: roomAId, token: 'token-a'),
      ),
    );
    expect(loaded.queue!.items.map((item) => item.track.title), [
      'First Track',
      'Second Track',
    ]);

    await tester.tap(find.byTooltip('Vote for First Track'));
    await tester.pumpAndSettle();
    expect(find.text('Vote counted. 4 votes remaining.'), findsOneWidget);
    expect(find.text('4 personal votes remaining'), findsOneWidget);
    expect(find.textContaining('5 votes'), findsOneWidget);
    await disposeHarness(tester, harness);
  });

  testWidgets('empty queue is a valid Room state', (tester) async {
    final harness = RoomHarness((request) async {
      switch (request.url.path) {
        case '/api/v1/sessions/me':
          return currentSession(roomAId);
        case '/api/v1/rooms/$roomAId':
          return apiResponse(room(roomAId, 'Empty Room'));
        case '/api/v1/rooms/$roomAId/queue':
          return apiResponse(queue());
        default:
          throw StateError('Unexpected request ${request.url.path}');
      }
    });
    addTearDown(harness.dispose);
    await harness.bootstrap();

    await tester.pumpWidget(appFor(harness, const RoomScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Empty Room'), findsWidgets);
    expect(find.text('The queue is empty.'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);

    await tester.tap(find.text('Search music'));
    await tester.pumpAndSettle();
    expect(find.byType(TrackSearchScreen), findsOneWidget);
    await disposeHarness(tester, harness);
  });

  testWidgets('reconnect warning keeps the last queue visible', (tester) async {
    final harness = RoomHarness((request) async {
      switch (request.url.path) {
        case '/api/v1/sessions/me':
          return currentSession(roomAId);
        case '/api/v1/rooms/$roomAId':
          return apiResponse(room(roomAId, 'Room A'));
        case '/api/v1/rooms/$roomAId/queue':
          return apiResponse(
            queue(items: [queuedTrack(1, 'kept', 'Still Visible')]),
          );
        default:
          throw StateError('Unexpected request ${request.url.path}');
      }
    }, reconnectDelay: const Duration(hours: 1));
    addTearDown(harness.dispose);
    await harness.bootstrap();

    await tester.pumpWidget(appFor(harness, const RoomScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Still Visible'), findsOneWidget);

    await harness.sockets.connections.single.disconnect();
    await tester.pump();

    expect(
      find.text('Live updates unavailable. Reconnecting…'),
      findsOneWidget,
    );
    expect(find.text('Still Visible'), findsOneWidget);
    expect(harness.sockets.requests, hasLength(1));
    await disposeHarness(tester, harness);
  });

  testWidgets('load failure exposes retry and retry can recover', (
    tester,
  ) async {
    var queueRequests = 0;
    final harness = RoomHarness((request) async {
      switch (request.url.path) {
        case '/api/v1/sessions/me':
          return currentSession(roomAId);
        case '/api/v1/rooms/$roomAId':
          return apiResponse(room(roomAId, 'Room A'));
        case '/api/v1/rooms/$roomAId/queue':
          queueRequests++;
          if (queueRequests == 1) {
            return apiError('INTERNAL_ERROR', status: 500);
          }
          return apiResponse(
            queue(items: [queuedTrack(1, 'recovered', 'Recovered Track')]),
          );
        default:
          throw StateError('Unexpected request ${request.url.path}');
      }
    });
    addTearDown(harness.dispose);
    await harness.bootstrap();

    await tester.pumpWidget(appFor(harness, const RoomScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('temporarily unavailable'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(queueRequests, 2);
    expect(find.text('Recovered Track'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    await disposeHarness(tester, harness);
  });

  testWidgets('successful room switch loads B without retaining A data', (
    tester,
  ) async {
    final harness = RoomHarness((request) async {
      final path = request.url.path;
      if (path == '/api/v1/sessions/me') return currentSession(roomAId);
      if (path == '/api/v1/rooms/join-by-qr') return joinedRoomB();
      if (path == '/api/v1/rooms/$roomAId') {
        return apiResponse(room(roomAId, 'Room A'));
      }
      if (path == '/api/v1/rooms/$roomAId/queue') {
        return apiResponse(queue(items: [queuedTrack(1, 'a', 'Room A Track')]));
      }
      if (path == '/api/v1/rooms/$roomBId') {
        return apiResponse(room(roomBId, 'Room B'));
      }
      if (path == '/api/v1/rooms/$roomBId/queue') {
        return apiResponse(queue(items: [queuedTrack(1, 'b', 'Room B Track')]));
      }
      throw StateError('Unexpected request $path');
    });
    addTearDown(harness.dispose);

    await tester.pumpWidget(appFor(harness, const SessionGateway()));
    await tester.pumpAndSettle();
    expect(find.text('Room A Track'), findsOneWidget);

    final session = harness.container.read(sessionControllerProvider.notifier);
    session.startRoomSwitch();
    await tester.pump();
    await session.join(qrCode: 'room-b-qr', nickname: 'Camille');
    await tester.pumpAndSettle();

    expect(harness.storage.token, 'token-b');
    expect(find.text('Room B'), findsWidgets);
    expect(find.text('Room B Track'), findsOneWidget);
    expect(find.text('Room A Track'), findsNothing);
    await disposeHarness(tester, harness);
  });

  testWidgets('leave removes Room data and returns to Join', (tester) async {
    final harness = RoomHarness((request) async {
      switch (request.url.path) {
        case '/api/v1/sessions/me':
          return currentSession(roomAId);
        case '/api/v1/rooms/$roomAId':
          return apiResponse(room(roomAId, 'Room A'));
        case '/api/v1/rooms/$roomAId/queue':
          return apiResponse(
            queue(items: [queuedTrack(1, 'a', 'Room A Track')]),
          );
        case '/api/v1/sessions/leave':
          return apiResponse({'left': true});
        default:
          throw StateError('Unexpected request ${request.url.path}');
      }
    });
    addTearDown(harness.dispose);

    await tester.pumpWidget(appFor(harness, const SessionGateway()));
    await tester.pumpAndSettle();
    expect(find.byType(RoomScreen), findsOneWidget);
    expect(find.text('Room A Track'), findsOneWidget);

    await tester.tap(find.text('Leave'));
    await tester.pump();
    await tester.runAsync(() async {
      for (
        var index = 0;
        index < 10 && harness.storage.token != null;
        index++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    });
    await tester.pumpAndSettle();

    expect(find.byType(RoomScreen), findsNothing);
    expect(find.byType(JoinScreen), findsOneWidget);
    expect(find.text('Room A Track'), findsNothing);
    expect(harness.storage.token, isNull);
    await disposeHarness(tester, harness);
  });
}
