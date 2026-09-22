import 'package:crowd_beats_front/models/queue.dart';
import 'package:crowd_beats_front/models/room.dart';
import 'package:crowd_beats_front/models/session.dart';
import 'package:crowd_beats_front/models/track.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures.dart';

void main() {
  test('room decodes documented required fields and nullable slug', () {
    final room = RoomDto.fromJson(roomJson);
    expect(room.id, roomJson['id']);
    expect(room.slug, isNull);
    expect(room.queueLimit, 20);
    expect(room.createdAt, DateTime.utc(2026, 9, 21, 8));
    expect(
      () => RoomDto.fromJson({...roomJson}..remove('max_votes_per_user')),
      throwsFormatException,
    );
    expect(
      () => RoomDto.fromJson({...roomJson, 'queue_limit': '20'}),
      throwsFormatException,
    );
  });

  test('join and current session retain their distinct contract shapes', () {
    final joined = JoinRoomResponseDto.fromJson({
      'room': roomJson,
      'session': {
        'id': 'session-id',
        'nickname': 'Camille',
        'role': 'guest',
        'token': 'opaque-token',
      },
      'ws': {'url': '/ws?room_id=${roomJson['id']}'},
    });
    expect(joined.session.token, 'opaque-token');
    expect(joined.ws.url, contains('/ws?room_id='));

    final current = CurrentSessionResponseDto.fromJson({
      'session': {
        'id': 'session-id',
        'room_id': roomJson['id'],
        'nickname': 'Camille',
        'role': 'guest',
        'status': 'active',
        'last_seen_at': '2026-09-21T08:01:00Z',
      },
    });
    expect(current.session.roomId, roomJson['id']);
    expect(current.session.status, 'active');
    expect(
      () => CurrentSessionResponseDto.fromJson({
        'session': {'id': 'session-id'},
      }),
      throwsFormatException,
    );
  });

  test('requests use exact snake_case and omit optional fields', () {
    expect(
      const JoinRoomRequestDto(qrCode: 'qr', nickname: 'Camille').toJson(),
      {'qr_code': 'qr', 'nickname': 'Camille'},
    );
    expect(
      const JoinRoomRequestDto(
        qrCode: 'qr',
        nickname: 'Camille',
        sessionToken: 'previous',
      ).toJson(),
      {'qr_code': 'qr', 'nickname': 'Camille', 'session_token': 'previous'},
    );
    expect(const HeartbeatRequestDto().toJson(), isEmpty);
    expect(const HeartbeatRequestDto(roomId: 'id').toJson(), {'room_id': 'id'});
    expect(const TrackProposalRequestDto(spotifyTrackId: 'id').toJson(), {
      'spotify_track_id': 'id',
    });
    expect(const VoteRequestDto(roomTrackId: 'id').toJson(), {
      'room_track_id': 'id',
    });
  });

  test('queue preserves nullable now playing and updated_at', () {
    final empty = QueueSnapshotDto.fromJson({
      'items': [],
      'now_playing': null,
      'updated_at': null,
    });
    expect(empty.items, isEmpty);
    expect(empty.nowPlaying, isNull);
    expect(empty.updatedAt, isNull);

    final snapshot = QueueSnapshotDto.fromJson({
      'items': [
        {
          'position': 1,
          'room_track_id': 'queued-id',
          'score': 2,
          'vote_count': 2,
          'track': spotifyTrackJson,
          'proposed_by': null,
        },
      ],
      'now_playing': {
        'room_track_id': 'playing-id',
        'vote_count': 3,
        'track': spotifyTrackJson,
        'proposed_by': 'Camille',
      },
      'updated_at': '2026-09-21T08:00:00Z',
    });
    expect(snapshot.items.single.track.artistNames, 'Artiste');
    expect(snapshot.items.single.proposedBy, isNull);
    expect(snapshot.nowPlaying?.roomTrackId, 'playing-id');
    expect(snapshot.nowPlaying?.proposedBy, 'Camille');
    expect(
      () => QueueSnapshotDto.fromJson({'items': [], 'now_playing': null}),
      throwsFormatException,
    );
  });

  test('proposal distinguishes created and duplicate response shapes', () {
    final created = TrackProposalResponseDto.fromJson({
      'room_track': {'id': 'new-id', 'status': 'queued', 'position': null},
      'duplicate': false,
    });
    expect(created.roomTrack?.id, 'new-id');
    expect(created.existingRoomTrack, isNull);

    final duplicate = TrackProposalResponseDto.fromJson({
      'existing_room_track': {
        'id': 'existing-id',
        'current_vote_count': 2,
        'position': 1,
      },
      'duplicate': true,
    });
    expect(duplicate.existingRoomTrack?.currentVoteCount, 2);
    expect(duplicate.roomTrack, isNull);
    expect(
      () => TrackProposalResponseDto.fromJson({
        'duplicate': true,
        'room_track': {'id': 'wrong', 'status': 'queued', 'position': null},
      }),
      throwsFormatException,
    );
  });

  test('Spotify and vote response require documented fields', () {
    expect(SpotifyTrackDto.fromJson(spotifyTrackJson).artistNames, 'Artiste');
    expect(SpotifySearchResponseDto.fromJson({'items': []}).items, isEmpty);
    expect(
      () => SpotifyTrackDto.fromJson({...spotifyTrackJson}..remove('uri')),
      throwsFormatException,
    );
    final vote = VoteResponseDto.fromJson({
      'vote_added': true,
      'room_track_id': 'track-id',
      'current_vote_count': 1,
      'votes_remaining': 4,
    });
    expect(vote.votesRemaining, 4);
    expect(
      () => VoteResponseDto.fromJson({
        'vote_added': true,
        'room_track_id': 'track-id',
        'current_vote_count': 1,
      }),
      throwsFormatException,
    );
  });
}
