import 'dart:async';
import 'dart:convert';

import 'package:crowd_beats_front/core/api/api_client.dart';
import 'package:crowd_beats_front/core/api/crowd_beats_api.dart';
import 'package:crowd_beats_front/core/config/app_providers.dart';
import 'package:crowd_beats_front/core/storage/session_storage.dart';
import 'package:crowd_beats_front/core/theme/app_theme.dart';
import 'package:crowd_beats_front/features/room/room_controller.dart';
import 'package:crowd_beats_front/features/search/track_search_controller.dart';
import 'package:crowd_beats_front/features/search/track_search_screen.dart';
import 'package:crowd_beats_front/features/session/session_controller.dart';
import 'package:crowd_beats_front/features/vote/vote_controller.dart';
import 'package:crowd_beats_front/models/track.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../fixtures.dart';
import '../../websocket_fakes.dart';

const roomAId = '11111111-1111-4111-8111-111111111111';
const roomBId = '22222222-2222-4222-8222-222222222222';
const trackAId = 'AAAAAAAAAAAAAAAAAAAAAA';
const trackBId = 'BBBBBBBBBBBBBBBBBBBBBB';
const sessionA = TrackSearchSession(roomId: roomAId, token: 'token-a');
const voteRoomAKey = RoomSessionKey(roomId: roomAId, token: 'token-a');

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

class SearchHarness {
  SearchHarness(Future<http.Response> Function(http.Request) handler)
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

http.Response currentSession(String roomId) => apiResponse({
  'session': {
    'id': 'session-$roomId',
    'room_id': roomId,
    'nickname': 'Camille',
    'role': 'guest',
    'status': 'active',
    'last_seen_at': '2026-09-21T08:00:00Z',
  },
});

Map<String, dynamic> track(String id, String title) => {
  ...spotifyTrackJson,
  'spotify_track_id': id,
  'title': title,
};

http.Response searchResults(List<Map<String, dynamic>> items) =>
    apiResponse({'items': items});

http.Response acceptedProposal() => apiResponse({
  'room_track': {'id': 'new-room-track', 'status': 'queued', 'position': null},
  'duplicate': false,
}, status: 201);

http.Response duplicateProposal() => apiResponse({
  'existing_room_track': {
    'id': 'existing-room-track',
    'current_vote_count': 3,
    'position': 2,
  },
  'duplicate': true,
});

Future<void> flushEvents([int count = 10]) async {
  for (var index = 0; index < count; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

ProviderSubscription<TrackSearchState> listenToSearch(SearchHarness harness) {
  return harness.container.listen(
    trackSearchControllerProvider(sessionA),
    (_, _) {},
    fireImmediately: true,
  );
}

void main() {
  test(
    'search sends trimmed query and preserves backend result order',
    () async {
      http.Request? searchRequest;
      final harness = SearchHarness((request) async {
        if (request.url.path == '/api/v1/sessions/me') {
          return currentSession(roomAId);
        }
        searchRequest = request;
        return searchResults([
          track(trackBId, 'Backend First'),
          track(trackAId, 'Backend Second'),
        ]);
      });
      addTearDown(harness.dispose);
      await harness.bootstrap();
      final subscription = listenToSearch(harness);
      addTearDown(subscription.close);

      await harness.container
          .read(trackSearchControllerProvider(sessionA).notifier)
          .search('  house music  ');

      expect(searchRequest?.url.path, '/api/v1/spotify/search');
      expect(searchRequest?.url.queryParameters['q'], 'house music');
      expect(searchRequest?.headers['authorization'], 'Bearer token-a');
      expect(
        harness.container
            .read(trackSearchControllerProvider(sessionA))
            .results
            .map((item) => item.title),
        ['Backend First', 'Backend Second'],
      );
    },
  );

  test('empty search result is a valid results state', () async {
    final harness = SearchHarness((request) async {
      if (request.url.path == '/api/v1/sessions/me') {
        return currentSession(roomAId);
      }
      return searchResults([]);
    });
    addTearDown(harness.dispose);
    await harness.bootstrap();
    final subscription = listenToSearch(harness);
    addTearDown(subscription.close);

    await harness.container
        .read(trackSearchControllerProvider(sessionA).notifier)
        .search('nothing here');
    final state = harness.container.read(
      trackSearchControllerProvider(sessionA),
    );
    expect(state.searchPhase, SearchPhase.results);
    expect(state.results, isEmpty);
  });

  test('transient search failure retains session and retry recovers', () async {
    var searches = 0;
    final harness = SearchHarness((request) async {
      if (request.url.path == '/api/v1/sessions/me') {
        return currentSession(roomAId);
      }
      searches++;
      if (searches == 1) throw http.ClientException('offline');
      return searchResults([track(trackAId, 'Recovered')]);
    });
    addTearDown(harness.dispose);
    await harness.bootstrap();
    final subscription = listenToSearch(harness);
    addTearDown(subscription.close);
    final controller = harness.container.read(
      trackSearchControllerProvider(sessionA).notifier,
    );

    await controller.search('recover');
    expect(
      harness.container
          .read(trackSearchControllerProvider(sessionA))
          .searchPhase,
      SearchPhase.error,
    );
    expect(harness.storage.token, 'token-a');

    await controller.retrySearch();
    expect(
      harness.container
          .read(trackSearchControllerProvider(sessionA))
          .results
          .single
          .title,
      'Recovered',
    );
  });

  test('older search response cannot replace a newer query', () async {
    final older = Completer<http.Response>();
    final newer = Completer<http.Response>();
    final harness = SearchHarness((request) async {
      if (request.url.path == '/api/v1/sessions/me') {
        return currentSession(roomAId);
      }
      return request.url.queryParameters['q'] == 'older'
          ? older.future
          : newer.future;
    });
    addTearDown(harness.dispose);
    await harness.bootstrap();
    final subscription = listenToSearch(harness);
    addTearDown(subscription.close);
    final controller = harness.container.read(
      trackSearchControllerProvider(sessionA).notifier,
    );

    final olderRequest = controller.search('older');
    final newerRequest = controller.search('newer');
    newer.complete(searchResults([track(trackBId, 'Newer Result')]));
    await newerRequest;
    older.complete(searchResults([track(trackAId, 'Older Result')]));
    await olderRequest;

    final state = harness.container.read(
      trackSearchControllerProvider(sessionA),
    );
    expect(state.query, 'newer');
    expect(state.results.single.title, 'Newer Result');
  });

  test(
    'proposal targets active room, deduplicates taps and leaves queue alone',
    () async {
      final proposal = Completer<http.Response>();
      var proposals = 0;
      final initialQueue = {
        'items': [
          {
            'position': 1,
            'room_track_id': 'existing-queue-item',
            'score': 2,
            'vote_count': 2,
            'track': track(trackBId, 'Existing Queue Track'),
            'proposed_by': null,
          },
        ],
        'now_playing': null,
        'updated_at': '2026-09-21T08:00:00Z',
      };
      http.Request? proposalRequest;
      final harness = SearchHarness((request) async {
        if (request.url.path == '/api/v1/sessions/me') {
          return currentSession(roomAId);
        }
        if (request.url.path == '/api/v1/rooms/$roomAId') {
          return apiResponse(roomJson);
        }
        if (request.url.path == '/api/v1/rooms/$roomAId/queue') {
          return apiResponse(initialQueue);
        }
        proposalRequest = request;
        proposals++;
        return proposal.future;
      });
      addTearDown(harness.dispose);
      await harness.bootstrap();
      final searchSubscription = listenToSearch(harness);
      addTearDown(searchSubscription.close);
      const roomKey = RoomSessionKey(roomId: roomAId, token: 'token-a');
      final roomSubscription = harness.container.listen(
        roomControllerProvider(roomKey),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(roomSubscription.close);
      await flushEvents();
      final queueBefore = harness.container
          .read(roomControllerProvider(roomKey))
          .queue;
      final selected = SpotifyTrackDto.fromJson(track(trackAId, 'Selected'));
      final controller = harness.container.read(
        trackSearchControllerProvider(sessionA).notifier,
      );

      final first = controller.propose(selected);
      final second = controller.propose(selected);
      await flushEvents();
      expect(proposals, 1);
      proposal.complete(acceptedProposal());
      await Future.wait([first, second]);

      expect(proposalRequest?.url.path, '/api/v1/rooms/$roomAId/tracks');
      expect(proposalRequest?.headers['authorization'], 'Bearer token-a');
      expect(jsonDecode(proposalRequest!.body), {'spotify_track_id': trackAId});
      final searchState = harness.container.read(
        trackSearchControllerProvider(sessionA),
      );
      expect(searchState.proposalPhase, ProposalPhase.accepted);
      expect(searchState.proposal?.roomTrack?.id, 'new-room-track');
      expect(
        harness.container.read(roomControllerProvider(roomKey)).queue,
        same(queueBefore),
      );
    },
  );

  test(
    'duplicate success preserves existing track and directs user to voting',
    () async {
      var proposals = 0;
      final harness = SearchHarness((request) async {
        if (request.url.path == '/api/v1/sessions/me') {
          return currentSession(roomAId);
        }
        proposals++;
        return duplicateProposal();
      });
      addTearDown(harness.dispose);
      await harness.bootstrap();
      final subscription = listenToSearch(harness);
      addTearDown(subscription.close);
      final controller = harness.container.read(
        trackSearchControllerProvider(sessionA).notifier,
      );

      await controller.propose(
        SpotifyTrackDto.fromJson(track(trackAId, 'Duplicate')),
      );
      final state = harness.container.read(
        trackSearchControllerProvider(sessionA),
      );
      expect(proposals, 1);
      expect(state.proposalPhase, ProposalPhase.duplicate);
      expect(state.proposalMessage, contains('already in the queue'));
      expect(state.proposal?.existingRoomTrack?.id, 'existing-room-track');
      expect(state.proposal?.existingRoomTrack?.position, 2);
    },
  );

  testWidgets('duplicate proposal exposes the shared vote action', (
    tester,
  ) async {
    var votes = 0;
    final harness = SearchHarness((request) async {
      if (request.url.path == '/api/v1/sessions/me') {
        return currentSession(roomAId);
      }
      if (request.url.path == '/api/v1/rooms/$roomAId/tracks') {
        return duplicateProposal();
      }
      if (request.url.path == '/api/v1/rooms/$roomAId/votes') {
        votes++;
        return apiResponse({
          'vote_added': true,
          'room_track_id': 'existing-room-track',
          'current_vote_count': 4,
          'votes_remaining': 3,
        });
      }
      throw StateError('Unexpected request ${request.url.path}');
    });
    addTearDown(harness.dispose);
    await harness.bootstrap();
    final subscription = listenToSearch(harness);
    await harness.container
        .read(trackSearchControllerProvider(sessionA).notifier)
        .propose(SpotifyTrackDto.fromJson(track(trackAId, 'Duplicate')));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const TrackSearchScreen(session: sessionA),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Vote for the existing track'), findsOneWidget);

    await tester.tap(find.byTooltip('Vote for this track'));
    await tester.pumpAndSettle();

    expect(votes, 1);
    expect(find.text('Vote counted. 3 votes remaining.'), findsOneWidget);
    final voteState = harness.container.read(
      voteControllerProvider(voteRoomAKey),
    );
    expect(
      voteState.actionFor('existing-room-track')?.response?.roomTrackId,
      'existing-room-track',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    subscription.close();
    harness.dispose();
  });

  testWidgets('search screen renders results and a valid empty state', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final harness = SearchHarness((request) async {
      if (request.url.path == '/api/v1/sessions/me') {
        return currentSession(roomAId);
      }
      if (request.url.queryParameters['q'] == 'empty') {
        return searchResults([]);
      }
      return searchResults([track(trackAId, 'A very long result title')]);
    });
    addTearDown(harness.dispose);
    await harness.bootstrap();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp(
          theme: AppTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.3),
              viewInsets: const EdgeInsets.only(bottom: 240),
            ),
            child: child!,
          ),
          home: const TrackSearchScreen(session: sessionA),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'house');
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('A very long result title'), findsOneWidget);
    expect(find.byTooltip('Propose A very long result title'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'empty');
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('No tracks found'), findsOneWidget);
    expect(find.text('Try another title, artist, or album.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    harness.dispose();
  });

  test('queue full and transient proposal failure are retryable', () async {
    var proposals = 0;
    final harness = SearchHarness((request) async {
      if (request.url.path == '/api/v1/sessions/me') {
        return currentSession(roomAId);
      }
      proposals++;
      if (proposals == 1) return apiError('QUEUE_FULL', status: 409);
      if (proposals == 2) throw http.ClientException('offline');
      return acceptedProposal();
    });
    addTearDown(harness.dispose);
    await harness.bootstrap();
    final subscription = listenToSearch(harness);
    addTearDown(subscription.close);
    final controller = harness.container.read(
      trackSearchControllerProvider(sessionA).notifier,
    );
    final selected = SpotifyTrackDto.fromJson(track(trackAId, 'Selected'));

    await controller.propose(selected);
    var state = harness.container.read(trackSearchControllerProvider(sessionA));
    expect(state.proposalMessage, contains('queue is full'));
    expect(state.proposalFailure?.backendCode, 'QUEUE_FULL');
    expect(harness.storage.token, 'token-a');

    await controller.propose(selected);
    state = harness.container.read(trackSearchControllerProvider(sessionA));
    expect(state.proposalMessage, contains('Network unavailable'));
    expect(harness.storage.token, 'token-a');

    await controller.propose(selected);
    expect(
      harness.container
          .read(trackSearchControllerProvider(sessionA))
          .proposalPhase,
      ProposalPhase.accepted,
    );
  });

  test('authoritative search 401 invalidates the matching session', () async {
    final harness = SearchHarness((request) async {
      if (request.url.path == '/api/v1/sessions/me') {
        return currentSession(roomAId);
      }
      return apiError('UNAUTHORIZED', status: 401);
    });
    addTearDown(harness.dispose);
    await harness.bootstrap();
    final subscription = listenToSearch(harness);
    addTearDown(subscription.close);

    await harness.container
        .read(trackSearchControllerProvider(sessionA).notifier)
        .search('expired');

    expect(harness.storage.token, isNull);
    expect(
      harness.container.read(sessionControllerProvider).phase,
      SessionPhase.invalid,
    );
  });

  test(
    'older search 401 still invalidates the unchanged active session',
    () async {
      final older = Completer<http.Response>();
      final newer = Completer<http.Response>();
      final harness = SearchHarness((request) async {
        if (request.url.path == '/api/v1/sessions/me') {
          return currentSession(roomAId);
        }
        return request.url.queryParameters['q'] == 'older'
            ? older.future
            : newer.future;
      });
      addTearDown(harness.dispose);
      await harness.bootstrap();
      final subscription = listenToSearch(harness);
      addTearDown(subscription.close);
      final controller = harness.container.read(
        trackSearchControllerProvider(sessionA).notifier,
      );

      final olderRequest = controller.search('older');
      final newerRequest = controller.search('newer');
      older.complete(apiError('UNAUTHORIZED', status: 401));
      await olderRequest;
      newer.complete(searchResults([track(trackBId, 'Ignored Result')]));
      await newerRequest;

      expect(harness.storage.token, isNull);
      expect(
        harness.container.read(sessionControllerProvider).phase,
        SessionPhase.invalid,
      );
    },
  );

  test(
    'late Room A search and proposal cannot affect or invalidate B',
    () async {
      final pending = Completer<http.Response>();
      final harness = SearchHarness((request) async {
        if (request.url.path == '/api/v1/sessions/me') {
          return currentSession(roomAId);
        }
        if (request.url.path == '/api/v1/rooms/join-by-qr') {
          return apiResponse({
            'room': {...roomJson, 'id': roomBId, 'name': 'Room B'},
            'session': {
              'id': 'session-b',
              'nickname': 'Camille',
              'role': 'guest',
              'token': 'token-b',
            },
            'ws': {'url': '/ws?room_id=$roomBId'},
          });
        }
        return pending.future;
      });
      addTearDown(harness.dispose);
      await harness.bootstrap();
      final subscription = listenToSearch(harness);
      addTearDown(subscription.close);
      final searchController = harness.container.read(
        trackSearchControllerProvider(sessionA).notifier,
      );
      final search = searchController.search('Room A query');
      final proposal = searchController.propose(
        SpotifyTrackDto.fromJson(track(trackAId, 'Room A Track')),
      );
      await flushEvents();

      final sessionController = harness.container.read(
        sessionControllerProvider.notifier,
      );
      sessionController.startRoomSwitch();
      await sessionController.join(qrCode: 'room-b-code', nickname: 'Camille');
      pending.complete(apiError('UNAUTHORIZED', status: 401));
      await Future.wait([search, proposal]);

      final sessionState = harness.container.read(sessionControllerProvider);
      expect(sessionState.active?.roomId, roomBId);
      expect(sessionState.active?.token, 'token-b');
      expect(harness.storage.token, 'token-b');
      final oldState = harness.container.read(
        trackSearchControllerProvider(sessionA),
      );
      expect(oldState.searchPhase, SearchPhase.loading);
      expect(oldState.proposalPhase, ProposalPhase.submitting);
    },
  );
}
