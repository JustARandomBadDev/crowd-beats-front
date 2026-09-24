import 'dart:convert';

import '../../models/json_fields.dart';
import '../../models/queue.dart';

sealed class RoomEvent {
  const RoomEvent({required this.roomId, required this.timestamp});

  final String roomId;
  final DateTime timestamp;

  factory RoomEvent.parse(Object? message) {
    final Object? decoded;
    if (message is String) {
      decoded = jsonDecode(message);
    } else {
      decoded = message;
    }
    final json = JsonFields.object(decoded, 'WebSocket event');
    final event = JsonFields.string(json, 'event');
    final roomId = JsonFields.string(json, 'room_id');
    final timestamp = JsonFields.dateTime(json, 'timestamp');
    if (!json.containsKey('payload')) {
      throw const FormatException('Missing field payload');
    }
    final payload = json['payload'];

    switch (event) {
      case 'sync_required':
        JsonFields.object(payload, 'sync_required payload');
        return SyncRequiredEvent(roomId: roomId, timestamp: timestamp);
      case 'queue_updated':
        return QueueUpdatedEvent(
          roomId: roomId,
          timestamp: timestamp,
          snapshot: QueueSnapshotDto.fromJson(payload),
        );
      case 'room_joined':
        final fields = JsonFields.object(payload, 'room_joined payload');
        JsonFields.string(fields, 'session_id');
        JsonFields.string(fields, 'nickname');
        break;
      case 'presence_updated':
        final fields = JsonFields.object(payload, 'presence_updated payload');
        JsonFields.integer(fields, 'active_users');
        break;
      case 'track_proposed':
        final fields = JsonFields.object(payload, 'track_proposed payload');
        JsonFields.string(fields, 'room_track_id');
        JsonFields.string(fields, 'spotify_track_id');
        JsonFields.string(fields, 'title');
        JsonFields.string(fields, 'artist_names');
        break;
      case 'vote_received':
        final fields = JsonFields.object(payload, 'vote_received payload');
        JsonFields.string(fields, 'room_track_id');
        JsonFields.integer(fields, 'current_vote_count');
        break;
      case 'track_deleted':
      case 'track_skipped':
      case 'track_playing':
      case 'track_played':
        final fields = JsonFields.object(payload, '$event payload');
        JsonFields.string(fields, 'room_track_id');
        break;
      default:
        return UnknownRoomEvent(
          roomId: roomId,
          timestamp: timestamp,
          name: event,
        );
    }
    return InformationalRoomEvent(
      roomId: roomId,
      timestamp: timestamp,
      name: event,
    );
  }
}

class SyncRequiredEvent extends RoomEvent {
  const SyncRequiredEvent({required super.roomId, required super.timestamp});
}

class QueueUpdatedEvent extends RoomEvent {
  const QueueUpdatedEvent({
    required super.roomId,
    required super.timestamp,
    required this.snapshot,
  });

  final QueueSnapshotDto snapshot;
}

class InformationalRoomEvent extends RoomEvent {
  const InformationalRoomEvent({
    required super.roomId,
    required super.timestamp,
    required this.name,
  });

  final String name;
}

class UnknownRoomEvent extends RoomEvent {
  const UnknownRoomEvent({
    required super.roomId,
    required super.timestamp,
    required this.name,
  });

  final String name;
}
