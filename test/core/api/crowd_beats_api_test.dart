import 'dart:convert';

import 'package:crowd_beats_front/core/api/api_client.dart';
import 'package:crowd_beats_front/core/api/crowd_beats_api.dart';
import 'package:crowd_beats_front/models/session.dart';
import 'package:crowd_beats_front/models/track.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../fixtures.dart';

void main() {
  test('typed service uses frozen methods, paths, DTOs and auth', () async {
    final requests = <http.Request>[];
    final roomId = roomJson['id'] as String;
    final client = ApiClient(
      baseUrl: 'http://localhost:8080/',
      httpClient: MockClient((request) async {
        requests.add(request);
        final route = '${request.method} ${request.url.path}';
        switch (route) {
          case 'GET /health/ready':
            return apiResponse({'status': 'ready'});
          case 'POST /api/v1/rooms/join-by-qr':
            return apiResponse({
              'room': roomJson,
              'session': {
                'id': 'session-id',
                'nickname': 'Camille',
                'role': 'guest',
                'token': 'new-token',
              },
              'ws': {'url': '/ws?room_id=$roomId'},
            });
          case _ when route == 'GET /api/v1/rooms/$roomId':
            return apiResponse(roomJson);
          case 'GET /api/v1/sessions/me':
            return apiResponse({
              'session': {
                'id': 'session-id',
                'room_id': roomId,
                'nickname': 'Camille',
                'role': 'guest',
                'status': 'active',
                'last_seen_at': '2026-09-21T08:01:00Z',
              },
            });
          case 'POST /api/v1/sessions/heartbeat':
            return apiResponse({'updated': true});
          case 'POST /api/v1/sessions/leave':
            return apiResponse({'left': true});
          case _ when route == 'GET /api/v1/rooms/$roomId/queue':
            return apiResponse({
              'items': [],
              'now_playing': null,
              'updated_at': null,
            });
          case 'GET /api/v1/spotify/search':
            return apiResponse({
              'items': [spotifyTrackJson],
            });
          case _ when route == 'POST /api/v1/rooms/$roomId/tracks':
            return apiResponse({
              'room_track': {
                'id': 'new-track-id',
                'status': 'queued',
                'position': null,
              },
              'duplicate': false,
            }, status: 201);
          case _ when route == 'POST /api/v1/rooms/$roomId/votes':
            return apiResponse({
              'vote_added': true,
              'room_track_id': 'new-track-id',
              'current_vote_count': 1,
              'votes_remaining': 4,
            });
          default:
            throw StateError(
              'Unexpected route ${request.method} ${request.url}',
            );
        }
      }),
    );
    addTearDown(client.close);
    final api = CrowdBeatsApi(client);

    expect((await api.readiness()).data.status, 'ready');
    final join = await api.joinRoom(
      const JoinRoomRequestDto(
        qrCode: 'qr-code',
        nickname: 'Camille',
        sessionToken: 'old-token',
      ),
    );
    expect(join.data.session.token, 'new-token');
    expect((await api.getRoom(roomId)).data.name, 'Le Bar');
    expect(
      (await api.getCurrentSession(token: 'new-token')).data.session.roomId,
      roomId,
    );
    expect(
      (await api.heartbeat(
        token: 'new-token',
        request: HeartbeatRequestDto(roomId: roomId),
      )).data.updated,
      isTrue,
    );
    expect((await api.leave(token: 'new-token')).data.left, isTrue);
    expect((await api.getQueue(roomId)).data.items, isEmpty);
    expect(
      (await api.searchSpotify(
        token: 'new-token',
        query: 'rock & roll',
      )).data.items.single.spotifyTrackId,
      spotifyTrackJson['spotify_track_id'],
    );
    final proposal = await api.proposeTrack(
      roomId: roomId,
      token: 'new-token',
      request: const TrackProposalRequestDto(spotifyTrackId: 'spotify-id'),
    );
    expect(proposal.statusCode, 201);
    expect(proposal.data.roomTrack?.id, 'new-track-id');
    expect(
      (await api.vote(
        roomId: roomId,
        token: 'new-token',
        request: const VoteRequestDto(roomTrackId: 'new-track-id'),
      )).data.votesRemaining,
      4,
    );

    expect(requests, hasLength(10));
    for (final index in [0, 1, 2, 6]) {
      expect(requests[index].headers.containsKey('authorization'), isFalse);
    }
    for (final index in [3, 4, 5, 7, 8, 9]) {
      expect(requests[index].headers['authorization'], 'Bearer new-token');
    }
    expect(jsonDecode(requests[1].body), {
      'qr_code': 'qr-code',
      'nickname': 'Camille',
      'session_token': 'old-token',
    });
    expect(jsonDecode(requests[4].body), {'room_id': roomId});
    expect(requests[5].body, isEmpty);
    expect(requests[7].url.queryParameters['q'], 'rock & roll');
    expect(jsonDecode(requests[8].body), {'spotify_track_id': 'spotify-id'});
    expect(jsonDecode(requests[9].body), {'room_track_id': 'new-track-id'});
  });

  test('duplicate proposal is a successful 200 with existing track', () async {
    final client = ApiClient(
      baseUrl: 'http://localhost:8080',
      httpClient: MockClient(
        (request) async => apiResponse({
          'existing_room_track': {
            'id': 'existing-id',
            'current_vote_count': 2,
            'position': 1,
          },
          'duplicate': true,
        }),
      ),
    );
    addTearDown(client.close);
    final result = await CrowdBeatsApi(client).proposeTrack(
      roomId: 'room-id',
      token: 'token',
      request: const TrackProposalRequestDto(spotifyTrackId: 'spotify-id'),
    );
    expect(result.statusCode, 200);
    expect(result.data.duplicate, isTrue);
    expect(result.data.existingRoomTrack?.id, 'existing-id');
  });

  test('readiness retains documented 503 not_ready payload', () async {
    final client = ApiClient(
      baseUrl: 'http://localhost:8080',
      httpClient: MockClient(
        (request) async => apiResponse({'status': 'not_ready'}, status: 503),
      ),
    );
    addTearDown(client.close);
    final result = await CrowdBeatsApi(client).readiness();
    expect(result.statusCode, 503);
    expect(result.data.status, 'not_ready');
  });
}
