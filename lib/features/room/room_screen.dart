import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_failure.dart';
import '../../models/queue.dart';
import '../../models/track.dart';
import '../search/track_search_controller.dart';
import '../search/track_search_screen.dart';
import '../session/session_controller.dart';
import 'room_controller.dart';

class RoomScreen extends ConsumerWidget {
  const RoomScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionState = ref.watch(sessionControllerProvider);
    final active = sessionState.active!;
    final roomKey = RoomSessionKey(roomId: active.roomId, token: active.token);
    final roomState = ref.watch(roomControllerProvider(roomKey));
    final roomController = ref.read(roomControllerProvider(roomKey).notifier);
    final sessionController = ref.read(sessionControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(roomState.room?.name ?? active.roomName ?? 'Crowd Beats'),
        actions: [
          IconButton(
            tooltip: 'Scan another room',
            onPressed: sessionState.busy
                ? null
                : () async {
                    await roomController.stop();
                    if (context.mounted) sessionController.startRoomSwitch();
                  },
            icon: const Icon(Icons.qr_code_scanner),
          ),
          TextButton(
            onPressed: sessionState.busy
                ? null
                : () async {
                    await roomController.stop();
                    await sessionController.leave();
                    if (context.mounted &&
                        ref.read(sessionControllerProvider).active?.token ==
                            active.token) {
                      roomController.resume();
                    }
                  },
            child: const Text('Leave'),
          ),
        ],
      ),
      body: !roomState.hasData
          ? roomState.initialLoading
                ? const Center(child: CircularProgressIndicator())
                : _LoadError(
                    message: roomLoadErrorMessage(roomState.initialError),
                    onRetry: roomController.loadInitial,
                  )
          : RefreshIndicator(
              onRefresh: () async {
                await roomController.refresh();
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    roomState.room!.name,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 4),
                  Text('Signed in as ${active.nickname}'),
                  if (_liveStatusMessage(roomState) case final message?) ...[
                    const SizedBox(height: 12),
                    _LiveStatus(
                      message: message,
                      syncing: roomState.synchronizing,
                    ),
                  ],
                  if (sessionState.message != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      sessionState.message!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  if (roomState.queue!.nowPlaying case final nowPlaying?) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Now playing',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    _NowPlayingCard(nowPlaying: nowPlaying),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    'Up next',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  if (roomState.queue!.items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Text(
                        'The queue is empty.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    for (final item in roomState.queue!.items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _QueueItemCard(item: item),
                      ),
                ],
              ),
            ),
      floatingActionButton: roomState.hasData
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TrackSearchScreen(
                    session: TrackSearchSession(
                      roomId: active.roomId,
                      token: active.token,
                    ),
                  ),
                ),
              ),
              icon: const Icon(Icons.search),
              label: const Text('Search music'),
            )
          : null,
    );
  }
}

class _LiveStatus extends StatelessWidget {
  const _LiveStatus({required this.message, required this.syncing});

  final String message;
  final bool syncing;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            if (syncing) ...[
              const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

String? _liveStatusMessage(RoomState state) {
  if (state.liveMessage != null) return state.liveMessage;
  if (state.synchronizing) return 'Synchronizing live queue…';
  return switch (state.connectionStatus) {
    LiveConnectionStatus.connecting => 'Connecting live updates…',
    LiveConnectionStatus.reconnecting =>
      'Live updates unavailable. Reconnecting…',
    LiveConnectionStatus.connected || LiveConnectionStatus.stopped => null,
  };
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

String roomLoadErrorMessage(Object? error) {
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
