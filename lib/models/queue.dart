import 'json_fields.dart';
import 'track.dart';

class QueueItemDto {
  const QueueItemDto({
    required this.position,
    required this.roomTrackId,
    required this.score,
    required this.voteCount,
    required this.track,
    required this.proposedBy,
  });

  final int position;
  final String roomTrackId;
  final int score;
  final int voteCount;
  final SpotifyTrackDto track;
  final String? proposedBy;

  factory QueueItemDto.fromJson(Object? value) {
    final json = JsonFields.object(value, 'queue item');
    return QueueItemDto(
      position: JsonFields.integer(json, 'position'),
      roomTrackId: JsonFields.string(json, 'room_track_id'),
      score: JsonFields.integer(json, 'score'),
      voteCount: JsonFields.integer(json, 'vote_count'),
      track: SpotifyTrackDto.fromJson(JsonFields.nested(json, 'track')),
      proposedBy: JsonFields.nullableString(json, 'proposed_by'),
    );
  }
}

class NowPlayingDto {
  const NowPlayingDto({
    required this.roomTrackId,
    required this.voteCount,
    required this.track,
    required this.proposedBy,
  });

  final String roomTrackId;
  final int voteCount;
  final SpotifyTrackDto track;
  final String? proposedBy;

  factory NowPlayingDto.fromJson(Object? value) {
    final json = JsonFields.object(value, 'now playing');
    return NowPlayingDto(
      roomTrackId: JsonFields.string(json, 'room_track_id'),
      voteCount: JsonFields.integer(json, 'vote_count'),
      track: SpotifyTrackDto.fromJson(JsonFields.nested(json, 'track')),
      proposedBy: JsonFields.nullableString(json, 'proposed_by'),
    );
  }
}

class QueueSnapshotDto {
  const QueueSnapshotDto({
    required this.items,
    required this.nowPlaying,
    required this.updatedAt,
  });

  final List<QueueItemDto> items;
  final NowPlayingDto? nowPlaying;
  final DateTime? updatedAt;

  factory QueueSnapshotDto.fromJson(Object? value) {
    final json = JsonFields.object(value, 'queue');
    if (!json.containsKey('now_playing')) {
      throw const FormatException('Missing field now_playing');
    }
    return QueueSnapshotDto(
      items: JsonFields.list(
        json,
        'items',
      ).map((item) => QueueItemDto.fromJson(item)).toList(),
      nowPlaying: json['now_playing'] == null
          ? null
          : NowPlayingDto.fromJson(json['now_playing']),
      updatedAt: JsonFields.nullableDateTime(json, 'updated_at'),
    );
  }
}
