import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_providers.dart';
import '../../models/queue.dart';
import '../../models/room.dart';

class RoomViewData {
  const RoomViewData({required this.room, required this.queue});

  final RoomDto room;
  final QueueSnapshotDto queue;
}

final roomDataProvider = FutureProvider.autoDispose
    .family<RoomViewData, String>((ref, roomId) async {
      final api = ref.watch(crowdBeatsApiProvider);
      final room = await api.getRoom(roomId);
      final queue = await api.getQueue(roomId);
      return RoomViewData(room: room.data, queue: queue.data);
    }, retry: (_, _) => null);
