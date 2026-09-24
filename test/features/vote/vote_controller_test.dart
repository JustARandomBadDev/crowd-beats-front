import 'dart:async';
import 'dart:convert';

import 'package:crowd_beats_front/core/api/api_client.dart';
import 'package:crowd_beats_front/core/api/crowd_beats_api.dart';
import 'package:crowd_beats_front/core/config/app_providers.dart';
import 'package:crowd_beats_front/core/storage/session_storage.dart';
import 'package:crowd_beats_front/features/room/room_controller.dart';
import 'package:crowd_beats_front/features/session/session_controller.dart';
import 'package:crowd_beats_front/features/vote/vote_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../fixtures.dart';
import '../../websocket_fakes.dart';

const roomAId = '11111111-1111-4111-8111-111111111111';
const roomBId = '22222222-2222-4222-8222-222222222222';
const roomTrackAId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const roomTrackBId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const roomAKey = RoomSessionKey(roomId: roomAId, token: 'token-a');

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

class VoteHarness {
  VoteHarness(Future<http.Response> Function(http.Request) handler)
    : storage = MemoryStorage('token-a'),
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
      ],
    );
  }

  final MemoryStorage storage;
  final FakeWebSocketTransport sockets;
  late final ApiClient client;
  late final ProviderContainer container;

  Future<void> bootstrap() =>
      container.read(sessionControllerProvider.notifier).bootstrap();

  void dispose() {
    container.dispose();
    client.close();
  }
}

http.Response currentSession() => apiResponse({
  'session': {
    'id': 'session-a',
    'room_id': roomAId,
    'nickname': 'Camille',
    'role': 'guest',
    'status': 'active',
    'last_seen_at': '2026-09-24T08:00:00Z',
  },
});

http.Response joinedRoomB() => apiResponse({
  'room': {...roomJson, 'id': roomBId, 'name': 'Room B'},
  'session': {
    'id': 'session-b',
    'nickname': 'Camille',
    'role': 'guest',
    'token': 'token-b',
  },
  'ws': {'url': '/ws?room_id=$roomBId'},
});

http.Response voteResponse(
  String roomTrackId, {
  required int currentVoteCount,
  required int votesRemaining,
}) => apiResponse({
  'vote_added': true,
  'room_track_id': roomTrackId,
  'current_vote_count': currentVoteCount,
  'votes_remaining': votesRemaining,
});

Map<String, dynamic> queue({
  required int firstVotes,
  required int secondVotes,
}) {
  final first = {
    'position': firstVotes >= secondVotes ? 1 : 2,
    'room_track_id': roomTrackAId,
    'score': firstVotes,
    'vote_count': firstVotes,
    'track': {...spotifyTrackJson, 'title': 'Track A'},
    'proposed_by': null,
  };
  final second = {
    'position': firstVotes >= secondVotes ? 2 : 1,
    'room_track_id': roomTrackBId,
    'score': secondVotes,
    'vote_count': secondVotes,
    'track': {
      ...spotifyTrackJson,
      'spotify_track_id': 'BBBBBBBBBBBBBBBBBBBBBB',
      'title': 'Track B',
    },
    'proposed_by': null,
  };
  return {
    'items': firstVotes >= secondVotes ? [first, second] : [second, first],
    'now_playing': null,
    'updated_at': secondVotes == 0
        ? '2026-09-24T08:00:00Z'
        : '2026-09-24T08:01:00Z',
  };
}

Future<void> flushEvents([int count = 12]) async {
  for (var index = 0; index < count; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

ProviderSubscription<VoteState> listenToVotes(VoteHarness harness) {
  return harness.container.listen(
    voteControllerProvider(roomAKey),
    (_, _) {},
    fireImmediately: true,
  );
}

void main() {
  test(
    'successful vote uses exact identity and does not mutate queue',
    () async {
      http.Request? captured;
      final initialQueue = queue(firstVotes: 1, secondVotes: 0);
      final harness = VoteHarness((request) async {
        switch (request.url.path) {
          case '/api/v1/sessions/me':
            return currentSession();
          case '/api/v1/rooms/$roomAId':
            return apiResponse({...roomJson, 'id': roomAId});
          case '/api/v1/rooms/$roomAId/queue':
            return apiResponse(initialQueue);
          case '/api/v1/rooms/$roomAId/votes':
            captured = request;
            return voteResponse(
              roomTrackAId,
              currentVoteCount: 2,
              votesRemaining: 4,
            );
          default:
            throw StateError('Unexpected request ${request.url.path}');
        }
      });
      addTearDown(harness.dispose);
      await harness.bootstrap();
      final voteSubscription = listenToVotes(harness);
      addTearDown(voteSubscription.close);
      final roomSubscription = harness.container.listen(
        roomControllerProvider(roomAKey),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(roomSubscription.close);
      await flushEvents();
      final queueBefore = harness.container
          .read(roomControllerProvider(roomAKey))
          .queue;

      await harness.container
          .read(voteControllerProvider(roomAKey).notifier)
          .vote(roomTrackAId);

      expect(captured?.url.path, '/api/v1/rooms/$roomAId/votes');
      expect(captured?.headers['authorization'], 'Bearer token-a');
      expect(jsonDecode(captured!.body), {'room_track_id': roomTrackAId});
      final voteState = harness.container.read(
        voteControllerProvider(roomAKey),
      );
      expect(voteState.votesRemaining, 4);
      expect(voteState.actionFor(roomTrackAId)?.response?.voteAdded, isTrue);
      expect(voteState.actionFor(roomTrackAId)?.response?.currentVoteCount, 2);
      expect(
        harness.container.read(roomControllerProvider(roomAKey)).queue,
        same(queueBefore),
      );
    },
  );

  test(
    'same-track taps deduplicate while other tracks remain independent',
    () async {
      final pending = <String, Completer<http.Response>>{
        roomTrackAId: Completer(),
        roomTrackBId: Completer(),
      };
      final calls = <String>[];
      final harness = VoteHarness((request) async {
        if (request.url.path == '/api/v1/sessions/me') return currentSession();
        final id =
            (jsonDecode(request.body) as Map<String, dynamic>)['room_track_id']
                as String;
        calls.add(id);
        return pending[id]!.future;
      });
      addTearDown(harness.dispose);
      await harness.bootstrap();
      final subscription = listenToVotes(harness);
      addTearDown(subscription.close);
      final controller = harness.container.read(
        voteControllerProvider(roomAKey).notifier,
      );

      final first = controller.vote(roomTrackAId);
      final duplicate = controller.vote(roomTrackAId);
      final independent = controller.vote(roomTrackBId);
      await flushEvents();
      expect(calls, [roomTrackAId, roomTrackBId]);

      pending[roomTrackBId]!.complete(
        voteResponse(roomTrackBId, currentVoteCount: 1, votesRemaining: 3),
      );
      await flushEvents();
      pending[roomTrackAId]!.complete(
        voteResponse(roomTrackAId, currentVoteCount: 2, votesRemaining: 4),
      );
      await Future.wait([first, duplicate, independent]);

      final state = harness.container.read(voteControllerProvider(roomAKey));
      expect(state.actionFor(roomTrackAId)?.phase, VotePhase.accepted);
      expect(state.actionFor(roomTrackBId)?.phase, VotePhase.accepted);
      expect(state.votesRemaining, 3);
    },
  );

  for (final scenario in [
    (
      code: 'ALREADY_VOTED_FOR_TRACK',
      status: 409,
      phase: VotePhase.alreadyVoted,
      message: 'already voted',
    ),
    (
      code: 'VOTE_LIMIT_REACHED',
      status: 409,
      phase: VotePhase.limitReached,
      message: 'vote limit',
    ),
    (
      code: 'ROOM_TRACK_NOT_ACTIVE',
      status: 409,
      phase: VotePhase.trackInactive,
      message: 'no longer available',
    ),
  ]) {
    test('${scenario.code} has specific feedback', () async {
      final harness = VoteHarness((request) async {
        if (request.url.path == '/api/v1/sessions/me') return currentSession();
        return apiError(scenario.code, status: scenario.status);
      });
      addTearDown(harness.dispose);
      await harness.bootstrap();
      final subscription = listenToVotes(harness);
      addTearDown(subscription.close);

      await harness.container
          .read(voteControllerProvider(roomAKey).notifier)
          .vote(roomTrackAId);

      final action = harness.container
          .read(voteControllerProvider(roomAKey))
          .actionFor(roomTrackAId)!;
      expect(action.phase, scenario.phase);
      expect(action.message, contains(scenario.message));
      expect(action.failure?.backendCode, scenario.code);
    });
  }

  test('temporary failure retains session and permits retry', () async {
    var votes = 0;
    final harness = VoteHarness((request) async {
      if (request.url.path == '/api/v1/sessions/me') return currentSession();
      votes++;
      if (votes == 1) throw http.ClientException('offline');
      return voteResponse(roomTrackAId, currentVoteCount: 2, votesRemaining: 4);
    });
    addTearDown(harness.dispose);
    await harness.bootstrap();
    final subscription = listenToVotes(harness);
    addTearDown(subscription.close);
    final controller = harness.container.read(
      voteControllerProvider(roomAKey).notifier,
    );

    await controller.vote(roomTrackAId);
    var action = harness.container
        .read(voteControllerProvider(roomAKey))
        .actionFor(roomTrackAId)!;
    expect(action.phase, VotePhase.error);
    expect(action.message, contains('Network unavailable'));
    expect(harness.storage.token, 'token-a');

    await controller.vote(roomTrackAId);
    action = harness.container
        .read(voteControllerProvider(roomAKey))
        .actionFor(roomTrackAId)!;
    expect(action.phase, VotePhase.accepted);
    expect(votes, 2);
  });

  test('authoritative 401 invalidates the matching session', () async {
    final harness = VoteHarness((request) async {
      if (request.url.path == '/api/v1/sessions/me') return currentSession();
      return apiError('UNAUTHORIZED', status: 401);
    });
    addTearDown(harness.dispose);
    await harness.bootstrap();
    final subscription = listenToVotes(harness);
    addTearDown(subscription.close);

    await harness.container
        .read(voteControllerProvider(roomAKey).notifier)
        .vote(roomTrackAId);

    expect(harness.storage.token, isNull);
    expect(
      harness.container.read(sessionControllerProvider).phase,
      SessionPhase.invalid,
    );
  });

  test('late Room A failure cannot affect Room B vote state', () async {
    final pending = Completer<http.Response>();
    final harness = VoteHarness((request) async {
      if (request.url.path == '/api/v1/sessions/me') return currentSession();
      if (request.url.path == '/api/v1/rooms/join-by-qr') return joinedRoomB();
      return pending.future;
    });
    addTearDown(harness.dispose);
    await harness.bootstrap();
    final subscription = listenToVotes(harness);
    addTearDown(subscription.close);
    final vote = harness.container
        .read(voteControllerProvider(roomAKey).notifier)
        .vote(roomTrackAId);
    await flushEvents();

    final session = harness.container.read(sessionControllerProvider.notifier);
    session.startRoomSwitch();
    await session.join(qrCode: 'room-b-qr', nickname: 'Camille');
    pending.complete(apiError('UNAUTHORIZED', status: 401));
    await vote;

    final sessionState = harness.container.read(sessionControllerProvider);
    expect(sessionState.active?.roomId, roomBId);
    expect(sessionState.active?.token, 'token-b');
    expect(harness.storage.token, 'token-b');
    const roomBKey = RoomSessionKey(roomId: roomBId, token: 'token-b');
    expect(
      harness.container.read(voteControllerProvider(roomBKey)).actions,
      isEmpty,
    );
  });

  test(
    'leave disposes vote state and late success cannot restore it',
    () async {
      final pending = Completer<http.Response>();
      final harness = VoteHarness((request) async {
        if (request.url.path == '/api/v1/sessions/me') return currentSession();
        if (request.url.path == '/api/v1/sessions/leave') {
          return apiResponse({'left': true});
        }
        return pending.future;
      });
      addTearDown(harness.dispose);
      await harness.bootstrap();
      final subscription = listenToVotes(harness);
      final vote = harness.container
          .read(voteControllerProvider(roomAKey).notifier)
          .vote(roomTrackAId);
      await flushEvents();

      await harness.container.read(sessionControllerProvider.notifier).leave();
      subscription.close();
      await flushEvents();
      pending.complete(
        voteResponse(roomTrackAId, currentVoteCount: 2, votesRemaining: 4),
      );
      await vote;

      expect(harness.storage.token, isNull);
      expect(
        harness.container.read(sessionControllerProvider).phase,
        SessionPhase.none,
      );
      expect(
        harness.container.read(voteControllerProvider(roomAKey)).actions,
        isEmpty,
      );
    },
  );

  test('queue changes only after authoritative queue_updated', () async {
    final initialQueue = queue(firstVotes: 1, secondVotes: 0);
    final harness = VoteHarness((request) async {
      switch (request.url.path) {
        case '/api/v1/sessions/me':
          return currentSession();
        case '/api/v1/rooms/$roomAId':
          return apiResponse({...roomJson, 'id': roomAId});
        case '/api/v1/rooms/$roomAId/queue':
          return apiResponse(initialQueue);
        case '/api/v1/rooms/$roomAId/votes':
          return voteResponse(
            roomTrackBId,
            currentVoteCount: 2,
            votesRemaining: 4,
          );
        default:
          throw StateError('Unexpected request ${request.url.path}');
      }
    });
    addTearDown(harness.dispose);
    await harness.bootstrap();
    final voteSubscription = listenToVotes(harness);
    addTearDown(voteSubscription.close);
    final roomSubscription = harness.container.listen(
      roomControllerProvider(roomAKey),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(roomSubscription.close);
    await flushEvents();

    await harness.container
        .read(voteControllerProvider(roomAKey).notifier)
        .vote(roomTrackBId);
    var roomState = harness.container.read(roomControllerProvider(roomAKey));
    expect(roomState.queue!.items.first.roomTrackId, roomTrackAId);
    expect(roomState.queue!.items.last.voteCount, 0);

    harness.sockets.connections.single.emit(
      jsonEncode({
        'event': 'queue_updated',
        'room_id': roomAId,
        'timestamp': '2026-09-24T08:01:00Z',
        'payload': queue(firstVotes: 1, secondVotes: 2),
      }),
    );
    await flushEvents();

    roomState = harness.container.read(roomControllerProvider(roomAKey));
    expect(roomState.queue!.items.first.roomTrackId, roomTrackBId);
    expect(roomState.queue!.items.first.voteCount, 2);
    expect(roomState.queue!.updatedAt, DateTime.parse('2026-09-24T08:01:00Z'));
  });
}
