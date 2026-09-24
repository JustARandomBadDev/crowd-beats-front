import 'json_fields.dart';

class SpotifyTrackDto {
  const SpotifyTrackDto({
    required this.spotifyTrackId,
    required this.title,
    required this.artistNames,
    required this.albumName,
    required this.durationMs,
    required this.imageUrl,
    required this.previewUrl,
    required this.uri,
  });

  final String spotifyTrackId;
  final String title;
  final String artistNames;
  final String albumName;
  final int durationMs;
  final String imageUrl;
  final String previewUrl;
  final String uri;

  factory SpotifyTrackDto.fromJson(Object? value) {
    final json = JsonFields.object(value, 'track');
    return SpotifyTrackDto(
      spotifyTrackId: JsonFields.string(json, 'spotify_track_id'),
      title: JsonFields.string(json, 'title'),
      artistNames: JsonFields.string(json, 'artist_names'),
      albumName: JsonFields.string(json, 'album_name'),
      durationMs: JsonFields.integer(json, 'duration_ms'),
      imageUrl: JsonFields.string(json, 'image_url'),
      previewUrl: JsonFields.string(json, 'preview_url'),
      uri: JsonFields.string(json, 'uri'),
    );
  }
}

class SpotifySearchResponseDto {
  const SpotifySearchResponseDto({required this.items});

  final List<SpotifyTrackDto> items;

  factory SpotifySearchResponseDto.fromJson(Object? value) {
    final json = JsonFields.object(value, 'spotify search');
    return SpotifySearchResponseDto(
      items: JsonFields.list(
        json,
        'items',
      ).map((item) => SpotifyTrackDto.fromJson(item)).toList(),
    );
  }
}

class TrackProposalRequestDto {
  const TrackProposalRequestDto({required this.spotifyTrackId});

  final String spotifyTrackId;

  Map<String, dynamic> toJson() => {'spotify_track_id': spotifyTrackId};
}

class ProposedRoomTrackDto {
  const ProposedRoomTrackDto({
    required this.id,
    required this.status,
    required this.position,
  });

  final String id;
  final String status;
  final int? position;

  factory ProposedRoomTrackDto.fromJson(Object? value) {
    final json = JsonFields.object(value, 'room_track');
    return ProposedRoomTrackDto(
      id: JsonFields.string(json, 'id'),
      status: JsonFields.string(json, 'status'),
      position: JsonFields.nullableInt(json, 'position'),
    );
  }
}

class ExistingRoomTrackDto {
  const ExistingRoomTrackDto({
    required this.id,
    required this.currentVoteCount,
    required this.position,
  });

  final String id;
  final int currentVoteCount;
  final int? position;

  factory ExistingRoomTrackDto.fromJson(Object? value) {
    final json = JsonFields.object(value, 'existing_room_track');
    return ExistingRoomTrackDto(
      id: JsonFields.string(json, 'id'),
      currentVoteCount: JsonFields.integer(json, 'current_vote_count'),
      position: JsonFields.nullableInt(json, 'position'),
    );
  }
}

class TrackProposalResponseDto {
  const TrackProposalResponseDto({
    required this.duplicate,
    required this.roomTrack,
    required this.existingRoomTrack,
  });

  final bool duplicate;
  final ProposedRoomTrackDto? roomTrack;
  final ExistingRoomTrackDto? existingRoomTrack;

  factory TrackProposalResponseDto.fromJson(Object? value) {
    final json = JsonFields.object(value, 'proposal');
    final duplicate = JsonFields.boolean(json, 'duplicate');
    final hasRoomTrack = json.containsKey('room_track');
    final hasExisting = json.containsKey('existing_room_track');
    if (hasRoomTrack == hasExisting || duplicate != hasExisting) {
      throw const FormatException('Invalid proposal response shape');
    }
    return TrackProposalResponseDto(
      duplicate: duplicate,
      roomTrack: hasRoomTrack
          ? ProposedRoomTrackDto.fromJson(json['room_track'])
          : null,
      existingRoomTrack: hasExisting
          ? ExistingRoomTrackDto.fromJson(json['existing_room_track'])
          : null,
    );
  }
}

class VoteRequestDto {
  const VoteRequestDto({required this.roomTrackId});

  final String roomTrackId;

  Map<String, dynamic> toJson() => {'room_track_id': roomTrackId};
}

class VoteResponseDto {
  const VoteResponseDto({
    required this.voteAdded,
    required this.roomTrackId,
    required this.currentVoteCount,
    required this.votesRemaining,
  });

  final bool voteAdded;
  final String roomTrackId;
  final int currentVoteCount;
  final int votesRemaining;

  factory VoteResponseDto.fromJson(Object? value) {
    final json = JsonFields.object(value, 'vote');
    return VoteResponseDto(
      voteAdded: JsonFields.boolean(json, 'vote_added'),
      roomTrackId: JsonFields.string(json, 'room_track_id'),
      currentVoteCount: JsonFields.integer(json, 'current_vote_count'),
      votesRemaining: JsonFields.integer(json, 'votes_remaining'),
    );
  }
}
