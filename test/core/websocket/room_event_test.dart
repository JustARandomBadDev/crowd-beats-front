import 'package:crowd_beats_front/core/websocket/room_event.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures.dart';

void main() {
  const roomId = '11111111-1111-4111-8111-111111111111';

  test('parses sync_required and a complete queue_updated snapshot', () {
    final sync = RoomEvent.parse({
      'event': 'sync_required',
      'room_id': roomId,
      'timestamp': '2026-09-21T08:00:00Z',
      'payload': <String, dynamic>{},
    });
    expect(sync, isA<SyncRequiredEvent>());

    final update =
        RoomEvent.parse({
              'event': 'queue_updated',
              'room_id': roomId,
              'timestamp': '2026-09-21T08:00:01Z',
              'payload': {
                'items': [
                  {
                    'position': 1,
                    'room_track_id': 'track-1',
                    'score': 4,
                    'vote_count': 4,
                    'track': spotifyTrackJson,
                    'proposed_by': null,
                  },
                ],
                'now_playing': null,
                'updated_at': '2026-09-21T08:00:01Z',
              },
            })
            as QueueUpdatedEvent;
    expect(update.snapshot.items.single.roomTrackId, 'track-1');
    expect(update.snapshot.updatedAt, DateTime.utc(2026, 9, 21, 8, 0, 1));
  });

  test(
    'unknown events are retained as unknown and malformed known events fail',
    () {
      final unknown = RoomEvent.parse({
        'event': 'future_event',
        'room_id': roomId,
        'timestamp': '2026-09-21T08:00:00Z',
        'payload': {'future': true},
      });
      expect(unknown, isA<UnknownRoomEvent>());

      expect(
        () => RoomEvent.parse({
          'event': 'queue_updated',
          'room_id': roomId,
          'timestamp': '2026-09-21T08:00:00Z',
          'payload': {'items': <Object>[]},
        }),
        throwsFormatException,
      );
    },
  );
}
