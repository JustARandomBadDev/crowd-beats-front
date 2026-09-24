import 'dart:async';

import 'package:crowd_beats_front/core/api/api_client.dart';
import 'package:crowd_beats_front/core/api/crowd_beats_api.dart';
import 'package:crowd_beats_front/core/config/app_providers.dart';
import 'package:crowd_beats_front/core/storage/session_storage.dart';
import 'package:crowd_beats_front/features/session/join_screen.dart';
import 'package:crowd_beats_front/features/session/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../fixtures.dart';

class MemorySessionStorage extends SessionStorage {
  MemorySessionStorage([this.token]);

  String? token;
  bool failSave = false;
  int clears = 0;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> saveToken(String value) async {
    if (failSave) throw StateError('storage failed');
    token = value;
  }

  @override
  Future<void> clearSession() async {
    clears++;
    token = null;
  }
}

class DelayedClearStorage extends MemorySessionStorage {
  DelayedClearStorage(super.token);

  final clearStarted = Completer<void>();
  final finishClear = Completer<void>();

  @override
  Future<void> clearSession() async {
    clears++;
    clearStarted.complete();
    await finishClear.future;
    token = null;
  }
}

http.Response currentSession(String roomId) => apiResponse({
  'session': {
    'id': 'session-id',
    'room_id': roomId,
    'nickname': 'Camille',
    'role': 'guest',
    'status': 'active',
    'last_seen_at': '2026-09-21T08:01:00Z',
  },
});

http.Response joined(String token, {String? roomId}) => apiResponse({
  'room': {...roomJson, 'id': roomId ?? roomJson['id']},
  'session': {
    'id': 'session-$token',
    'nickname': 'Camille',
    'role': 'guest',
    'token': token,
  },
  'ws': {'url': '/ws?room_id=${roomId ?? roomJson['id']}'},
});

class Harness {
  Harness(this.storage, Future<http.Response> Function(http.Request) handler) {
    client = ApiClient(
      baseUrl: 'http://localhost:8080',
      httpClient: MockClient(handler),
    );
    container = ProviderContainer(
      overrides: [
        sessionStorageProvider.overrideWithValue(storage),
        crowdBeatsApiProvider.overrideWithValue(CrowdBeatsApi(client)),
      ],
    );
  }

  final MemorySessionStorage storage;
  late final ApiClient client;
  late final ProviderContainer container;

  SessionController get controller =>
      container.read(sessionControllerProvider.notifier);
  SessionState get state => container.read(sessionControllerProvider);

  void dispose() {
    container.dispose();
    client.close();
  }
}

void main() {
  final roomId = roomJson['id'] as String;

  test('no stored token enters Join without an API request', () async {
    final h = Harness(
      MemorySessionStorage(),
      (_) async => throw StateError('unexpected'),
    );
    addTearDown(h.dispose);
    await h.controller.bootstrap();
    expect(h.state.phase, SessionPhase.none);
    expect(h.controller.heartbeatScheduled, isFalse);
  });

  test('valid stored token restores room and schedules heartbeat', () async {
    final h = Harness(
      MemorySessionStorage('old'),
      (_) async => currentSession(roomId),
    );
    addTearDown(h.dispose);
    await h.controller.bootstrap();
    expect(h.state.phase, SessionPhase.active);
    expect(h.state.active?.roomId, roomId);
    expect(h.storage.token, 'old');
    expect(h.controller.heartbeatScheduled, isTrue);
  });

  test('invalid stored token is deleted and enters Join', () async {
    final h = Harness(
      MemorySessionStorage('old'),
      (_) async => apiError('UNAUTHORIZED', status: 401),
    );
    addTearDown(h.dispose);
    await h.controller.bootstrap();
    expect(h.state.phase, SessionPhase.invalid);
    expect(h.storage.token, isNull);
    expect(h.storage.clears, 1);
  });

  test('transient restore error retains token and offers retry', () async {
    var calls = 0;
    final h = Harness(MemorySessionStorage('old'), (_) async {
      calls++;
      if (calls == 1) throw http.ClientException('offline');
      return currentSession(roomId);
    });
    addTearDown(h.dispose);
    await h.controller.bootstrap();
    expect(h.state.phase, SessionPhase.error);
    expect(h.storage.token, 'old');
    await h.controller.bootstrap();
    expect(h.state.phase, SessionPhase.active);
  });

  test('successful join persists returned token before room state', () async {
    final h = Harness(MemorySessionStorage(), (_) async => joined('new'));
    addTearDown(h.dispose);
    await h.controller.bootstrap();
    await h.controller.join(qrCode: 'raw-code', nickname: ' Camille ');
    expect(h.storage.token, 'new');
    expect(h.state.phase, SessionPhase.active);
    expect(h.state.active?.nickname, 'Camille');
  });

  test('invalid QR leaves Join usable and never stores token', () async {
    final h = Harness(
      MemorySessionStorage(),
      (_) async => apiError('INVALID_QR_CODE', status: 403),
    );
    addTearDown(h.dispose);
    await h.controller.bootstrap();
    await h.controller.join(qrCode: 'expired', nickname: 'Camille');
    expect(h.state.phase, SessionPhase.none);
    expect(h.state.message, contains('invalid or expired'));
    expect(h.storage.token, isNull);
  });

  testWidgets('Join screen displays backend QR error', (tester) async {
    final h = Harness(
      MemorySessionStorage(),
      (_) async => apiError('INVALID_QR_CODE', status: 403),
    );
    addTearDown(h.dispose);
    await h.controller.bootstrap();
    await h.controller.join(qrCode: 'expired', nickname: 'Camille');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: h.container,
        child: const MaterialApp(home: JoinScreen()),
      ),
    );
    expect(
      find.text('This QR code is invalid or expired. Scan a new code.'),
      findsOneWidget,
    );
  });

  test('duplicate Join submits one request', () async {
    final response = Completer<http.Response>();
    var joins = 0;
    final h = Harness(MemorySessionStorage(), (_) {
      joins++;
      return response.future;
    });
    addTearDown(h.dispose);
    await h.controller.bootstrap();
    final first = h.controller.join(qrCode: 'raw', nickname: 'Camille');
    final second = h.controller.join(qrCode: 'raw', nickname: 'Camille');
    await Future<void>.delayed(Duration.zero);
    expect(joins, 1);
    response.complete(joined('new'));
    await Future.wait([first, second]);
    expect(h.storage.token, 'new');
  });

  test('room switch replaces token only after successful QR join', () async {
    final nextRoomId = '22222222-2222-4222-8222-222222222222';
    var joins = 0;
    final h = Harness(MemorySessionStorage('old'), (request) async {
      if (request.url.path.endsWith('/sessions/me')) {
        return currentSession(roomId);
      }
      joins++;
      expect(request.body, contains('"session_token":"old"'));
      if (joins == 1) return apiError('INVALID_QR_CODE', status: 403);
      return joined('new', roomId: nextRoomId);
    });
    addTearDown(h.dispose);
    await h.controller.bootstrap();
    h.controller.startRoomSwitch();
    await h.controller.join(qrCode: 'bad', nickname: 'Camille');
    expect(h.storage.token, 'old');
    expect(h.state.active?.roomId, roomId);
    expect(h.state.switching, isTrue);
    await h.controller.join(qrCode: 'good', nickname: 'Camille');
    expect(h.storage.token, 'new');
    expect(h.state.active?.roomId, nextRoomId);
    expect(h.state.switching, isFalse);
  });

  test(
    'storage failure after join blocks Room until saving succeeds',
    () async {
      final storage = MemorySessionStorage()..failSave = true;
      final h = Harness(storage, (_) async => joined('new'));
      addTearDown(h.dispose);
      await h.controller.bootstrap();
      await h.controller.join(qrCode: 'raw', nickname: 'Camille');
      expect(h.state.phase, SessionPhase.error);
      expect(h.state.pendingJoin?.token, 'new');
      expect(h.controller.heartbeatScheduled, isFalse);
      storage.failSave = false;
      await h.controller.retrySave();
      expect(h.state.phase, SessionPhase.active);
      expect(storage.token, 'new');
    },
  );

  test('leave succeeds and stops heartbeat', () async {
    final h = Harness(MemorySessionStorage('old'), (request) async {
      if (request.url.path.endsWith('/sessions/me')) {
        return currentSession(roomId);
      }
      return apiResponse({'left': true});
    });
    addTearDown(h.dispose);
    await h.controller.bootstrap();
    expect(h.controller.heartbeatScheduled, isTrue);
    await h.controller.leave();
    expect(h.state.phase, SessionPhase.none);
    expect(h.storage.token, isNull);
    expect(h.controller.heartbeatScheduled, isFalse);
  });

  test('already invalid leave clears local token', () async {
    final h = Harness(MemorySessionStorage('old'), (request) async {
      if (request.url.path.endsWith('/sessions/me')) {
        return currentSession(roomId);
      }
      return apiError('UNAUTHORIZED', status: 401);
    });
    addTearDown(h.dispose);
    await h.controller.bootstrap();
    await h.controller.leave();
    expect(h.state.phase, SessionPhase.invalid);
    expect(h.storage.token, isNull);
  });

  test('unexpected leave response retains session for retry', () async {
    final h = Harness(MemorySessionStorage('old'), (request) async {
      if (request.url.path.endsWith('/sessions/me')) {
        return currentSession(roomId);
      }
      return apiResponse({'left': false});
    });
    addTearDown(h.dispose);
    await h.controller.bootstrap();
    await h.controller.leave();
    expect(h.state.phase, SessionPhase.active);
    expect(h.storage.token, 'old');
    expect(h.controller.heartbeatScheduled, isTrue);
  });

  test('transient leave error keeps usable room and token', () async {
    final h = Harness(MemorySessionStorage('old'), (request) async {
      if (request.url.path.endsWith('/sessions/me')) {
        return currentSession(roomId);
      }
      throw http.ClientException('offline');
    });
    addTearDown(h.dispose);
    await h.controller.bootstrap();
    await h.controller.leave();
    expect(h.state.phase, SessionPhase.active);
    expect(h.storage.token, 'old');
    expect(h.controller.heartbeatScheduled, isTrue);
    expect(h.state.message, contains('retry'));
  });

  test(
    'invalid heartbeat clears session; transient heartbeat retains it',
    () async {
      var heartbeats = 0;
      final h = Harness(MemorySessionStorage('old'), (request) async {
        if (request.url.path.endsWith('/sessions/me')) {
          return currentSession(roomId);
        }
        heartbeats++;
        if (heartbeats == 1) throw http.ClientException('offline');
        return apiError('UNAUTHORIZED', status: 401);
      });
      addTearDown(h.dispose);
      await h.controller.bootstrap();
      await h.controller.heartbeatNow();
      expect(h.state.phase, SessionPhase.active);
      expect(h.storage.token, 'old');
      await h.controller.heartbeatNow();
      expect(h.state.phase, SessionPhase.invalid);
      expect(h.storage.token, isNull);
      expect(h.controller.heartbeatScheduled, isFalse);
    },
  );

  test(
    'session invalidation blocks a new join until token deletion ends',
    () async {
      final storage = DelayedClearStorage('old');
      var joins = 0;
      final h = Harness(storage, (request) async {
        if (request.url.path.endsWith('/sessions/me')) {
          return currentSession(roomId);
        }
        joins++;
        return joined('new');
      });
      addTearDown(h.dispose);
      await h.controller.bootstrap();

      final invalidation = h.controller.invalidateFromServer(token: 'old');
      await storage.clearStarted.future;
      expect(h.state.busy, isTrue);
      h.controller.startRoomSwitch();
      await h.controller.join(qrCode: 'new-room', nickname: 'Camille');

      expect(joins, 0);
      expect(storage.token, 'old');
      storage.finishClear.complete();
      await invalidation;
      expect(h.state.phase, SessionPhase.invalid);
      expect(storage.token, isNull);
    },
  );
}
