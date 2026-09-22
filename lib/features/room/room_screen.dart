import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_failure.dart';
import '../../models/queue.dart';
import '../../models/track.dart';
import '../session/session_controller.dart';
import 'room_data.dart';

class RoomScreen extends ConsumerWidget {
  const RoomScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionState = ref.watch(sessionControllerProvider);
    final active = sessionState.active!;
    final roomData = ref.watch(roomDataProvider(active.roomId));
    final sessionController = ref.read(sessionControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          roomData.value?.room.name ?? active.roomName ?? 'Crowd Beats',
        ),
        actions: [
          IconButton(
            tooltip: 'Scan another room',
            onPressed: sessionState.busy
                ? null
                : sessionController.startRoomSwitch,
            icon: const Icon(Icons.qr_code_scanner),
          ),
          TextButton(
            onPressed: sessionState.busy ? null : sessionController.leave,
            child: const Text('Leave'),
          ),
        ],
      ),
      body: roomData.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _LoadError(
          message: roomLoadErrorMessage(error),
          onRetry: () => ref.invalidate(roomDataProvider(active.roomId)),
        ),
        data: (data) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(roomDataProvider(active.roomId));
            try {
              await ref.read(roomDataProvider(active.roomId).future);
            } on Object {
              // The provider exposes the failure through the Room error state.
            }
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                data.room.name,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 4),
              Text('Signed in as ${active.nickname}'),
              if (sessionState.message != null) ...[
                const SizedBox(height: 12),
                Text(
                  sessionState.message!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (data.queue.nowPlaying case final nowPlaying?) ...[
                const SizedBox(height: 24),
                Text(
                  'Now playing',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                _NowPlayingCard(nowPlaying: nowPlaying),
              ],
              const SizedBox(height: 24),
              Text('Up next', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (data.queue.items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'The queue is empty.',
                    textAlign: TextAlign.center,
                  ),
                )
              else
                for (final item in data.queue.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _QueueItemCard(item: item),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _NowPlayingCard extends StatelessWidget {
  const _NowPlayingCard({required this.nowPlaying});

  final NowPlayingDto nowPlaying;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            _Artwork(track: nowPlaying.track),
            const SizedBox(width: 12),
            Expanded(
              child: _TrackDetails(
                track: nowPlaying.track,
                details: _voteLabel(nowPlaying.voteCount),
                proposedBy: nowPlaying.proposedBy,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueueItemCard extends StatelessWidget {
  const _QueueItemCard({required this.item});

  final QueueItemDto item;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Text(
                '${item.position}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(width: 8),
            _Artwork(track: item.track),
            const SizedBox(width: 12),
            Expanded(
              child: _TrackDetails(
                track: item.track,
                details: 'Score ${item.score} · ${_voteLabel(item.voteCount)}',
                proposedBy: item.proposedBy,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackDetails extends StatelessWidget {
  const _TrackDetails({
    required this.track,
    required this.details,
    required this.proposedBy,
  });

  final SpotifyTrackDto track;
  final String details;
  final String? proposedBy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          track.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(track.artistNames, maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        Text(details, style: Theme.of(context).textTheme.bodySmall),
        if (proposedBy case final nickname?)
          Text(
            'Proposed by $nickname',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.track});

  final SpotifyTrackDto track;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.music_note)),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox.square(
        dimension: 56,
        child: track.imageUrl.isEmpty
            ? placeholder
            : Image.network(
                track.imageUrl,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : const Center(child: CircularProgressIndicator()),
                errorBuilder: (context, error, stackTrace) => placeholder,
              ),
      ),
    );
  }
}

String _voteLabel(int count) => count == 1 ? '1 vote' : '$count votes';

String roomLoadErrorMessage(Object error) {
  if (error is! ApiFailure) {
    return 'Could not load this room. Please retry.';
  }
  switch (error.category) {
    case ApiFailureCategory.transport:
      return 'Network unavailable. Check your connection and retry.';
    case ApiFailureCategory.timeout:
      return 'The request timed out. Please retry.';
    case ApiFailureCategory.invalidJson:
    case ApiFailureCategory.protocol:
      return 'The backend returned an unexpected response. Please retry.';
    case ApiFailureCategory.backend:
      if (error.statusCode != null && error.statusCode! >= 500) {
        return 'The backend is temporarily unavailable. Please retry.';
      }
      if (error.backendCode == 'NOT_FOUND') {
        return 'This room is no longer available.';
      }
      return 'Could not load this room. Please retry.';
  }
}
