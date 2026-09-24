import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_failure.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../models/queue.dart';
import '../../models/track.dart';
import '../search/track_search_controller.dart';
import '../search/track_search_screen.dart';
import '../session/session_controller.dart';
import '../vote/vote_action.dart';
import '../vote/vote_controller.dart';
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
    final voteState = ref.watch(voteControllerProvider(roomKey));
    final voteController = ref.read(voteControllerProvider(roomKey).notifier);
    final sessionController = ref.read(sessionControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.graphic_eq_rounded,
              size: 22,
              color: AppColors.purpleLight,
            ),
            SizedBox(width: AppSpacing.small),
            Flexible(
              child: Text(
                'CrowdBeats',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Scan another room',
            onPressed: sessionState.busy
                ? null
                : () async {
                    await roomController.stop();
                    if (context.mounted) sessionController.startRoomSwitch();
                  },
            icon: const Icon(Icons.qr_code_scanner_rounded),
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
            child: sessionState.busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Leave'),
          ),
          const SizedBox(width: AppSpacing.small),
        ],
      ),
      body: !roomState.hasData
          ? roomState.initialLoading
                ? const AppLoadingState(label: 'Loading the room…')
                : _LoadError(
                    message: roomLoadErrorMessage(roomState.initialError),
                    onRetry: roomController.loadInitial,
                  )
          : RefreshIndicator(
              onRefresh: () async => roomController.refresh(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.large,
                  AppSpacing.small,
                  AppSpacing.large,
                  AppSpacing.xxLarge,
                ),
                children: [
                  _RoomHeader(
                    roomName: roomState.room!.name,
                    nickname: active.nickname,
                    state: roomState,
                  ),
                  if (_liveStatusMessage(roomState) case final message?) ...[
                    const SizedBox(height: AppSpacing.medium),
                    _LiveStatus(
                      message: message,
                      syncing: roomState.synchronizing,
                    ),
                  ],
                  if (sessionState.message != null) ...[
                    const SizedBox(height: AppSpacing.medium),
                    AppMessageCard(
                      message: sessionState.message!,
                      tone: AppMessageTone.error,
                      compact: true,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xLarge),
                  const AppSectionHeader(label: 'Now playing'),
                  const SizedBox(height: AppSpacing.small),
                  if (roomState.queue!.nowPlaying case final nowPlaying?)
                    _NowPlayingCard(
                      nowPlaying: nowPlaying,
                      voteAction: voteState.actionFor(nowPlaying.roomTrackId),
                      onVote: () => voteController.vote(nowPlaying.roomTrackId),
                    )
                  else
                    const _NoTrackPlaying(),
                  const SizedBox(height: AppSpacing.xLarge),
                  AppSectionHeader(
                    label: 'Up next',
                    trailing: voteState.votesRemaining == null
                        ? null
                        : AppStatusChip(
                            label: voteState.votesRemaining == 1
                                ? '1 personal vote remaining'
                                : '${voteState.votesRemaining} personal votes remaining',
                            icon: Icons.how_to_vote_outlined,
                          ),
                  ),
                  const SizedBox(height: AppSpacing.small),
                  if (roomState.queue!.items.isEmpty)
                    const _EmptyQueue()
                  else
                    for (final item in roomState.queue!.items)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: AppSpacing.small,
                        ),
                        child: _QueueItemCard(
                          item: item,
                          voteAction: voteState.actionFor(item.roomTrackId),
                          onVote: () => voteController.vote(item.roomTrackId),
                        ),
                      ),
                ],
              ),
            ),
      bottomNavigationBar: roomState.hasData
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(
                AppSpacing.large,
                AppSpacing.small,
                AppSpacing.large,
                AppSpacing.large,
              ),
              child: FilledButton.icon(
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
                icon: const Icon(Icons.add_rounded),
                label: const Text('Search music'),
              ),
            )
          : null,
    );
  }
}

class _RoomHeader extends StatelessWidget {
  const _RoomHeader({
    required this.roomName,
    required this.nickname,
    required this.state,
  });

  final String roomName;
  final String nickname;
  final RoomState state;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('YOU’RE IN', style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: AppSpacing.xSmall),
              Text(
                roomName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.xSmall),
              Text(
                'Listening as $nickname',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.medium),
        _ConnectionChip(state: state),
      ],
    );
  }
}

class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip({required this.state});

  final RoomState state;

  @override
  Widget build(BuildContext context) {
    if (state.synchronizing) {
      return const AppStatusChip(
        label: 'SYNCING',
        icon: Icons.sync_rounded,
        tone: AppMessageTone.warning,
      );
    }
    return switch (state.connectionStatus) {
      LiveConnectionStatus.connected => const AppStatusChip(
        label: 'LIVE',
        icon: Icons.circle,
        tone: AppMessageTone.success,
      ),
      LiveConnectionStatus.connecting => const AppStatusChip(
        label: 'CONNECTING',
        icon: Icons.sync_rounded,
      ),
      LiveConnectionStatus.reconnecting => const AppStatusChip(
        label: 'RECONNECTING',
        icon: Icons.sync_problem_rounded,
        tone: AppMessageTone.warning,
      ),
      LiveConnectionStatus.stopped => const AppStatusChip(
        label: 'OFFLINE',
        icon: Icons.cloud_off_outlined,
        tone: AppMessageTone.warning,
      ),
    };
  }
}

class _LiveStatus extends StatelessWidget {
  const _LiveStatus({required this.message, required this.syncing});

  final String message;
  final bool syncing;

  @override
  Widget build(BuildContext context) {
    return AppMessageCard(
      message: message,
      tone: syncing ? AppMessageTone.neutral : AppMessageTone.warning,
      icon: syncing ? Icons.sync_rounded : Icons.cloud_off_outlined,
      compact: true,
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
        padding: const EdgeInsets.all(AppSpacing.xLarge),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: AppMessageCard(
            title: 'Could not load the room',
            message: message,
            tone: AppMessageTone.error,
            action: FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ),
        ),
      ),
    );
  }
}

class _NowPlayingCard extends StatelessWidget {
  const _NowPlayingCard({
    required this.nowPlaying,
    required this.voteAction,
    required this.onVote,
  });

  final NowPlayingDto nowPlaying;
  final TrackVoteState? voteAction;
  final VoidCallback onVote;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.large),
      decoration: BoxDecoration(
        color: AppColors.surfaceStrong,
        borderRadius: BorderRadius.circular(AppRadii.large),
        border: Border.all(color: AppColors.purpleMuted),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TrackArtwork(
                imageUrl: nowPlaying.track.imageUrl,
                size: 78,
                radius: AppRadii.medium,
              ),
              const SizedBox(width: AppSpacing.large),
              Expanded(
                child: _TrackDetails(
                  track: nowPlaying.track,
                  details: _voteLabel(nowPlaying.voteCount),
                  proposedBy: nowPlaying.proposedBy,
                  prominent: true,
                ),
              ),
              const SizedBox(width: AppSpacing.small),
              VoteButton(
                trackTitle: nowPlaying.track.title,
                action: voteAction,
                onVote: onVote,
              ),
            ],
          ),
          VoteFeedback(action: voteAction),
        ],
      ),
    );
  }
}

class _NoTrackPlaying extends StatelessWidget {
  const _NoTrackPlaying();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.large),
      decoration: BoxDecoration(
        color: AppColors.backgroundRaised,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        children: [
          const Icon(Icons.music_off_outlined, color: AppColors.textMuted),
          const SizedBox(width: AppSpacing.medium),
          Expanded(
            child: Text(
              'Nothing is playing right now.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueItemCard extends StatelessWidget {
  const _QueueItemCard({
    required this.item,
    required this.voteAction,
    required this.onVote,
  });

  final QueueItemDto item;
  final TrackVoteState? voteAction;
  final VoidCallback onVote;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.medium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    '${item.position}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.purpleLight,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.small),
                TrackArtwork(imageUrl: item.track.imageUrl, size: 54),
                const SizedBox(width: AppSpacing.medium),
                Expanded(
                  child: _TrackDetails(
                    track: item.track,
                    details:
                        'Score ${item.score}  ·  ${_voteLabel(item.voteCount)}',
                    proposedBy: item.proposedBy,
                  ),
                ),
                const SizedBox(width: AppSpacing.small),
                VoteButton(
                  trackTitle: item.track.title,
                  action: voteAction,
                  onVote: onVote,
                ),
              ],
            ),
            VoteFeedback(action: voteAction),
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
    this.prominent = false,
  });

  final SpotifyTrackDto track;
  final String details;
  final String? proposedBy;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          track.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: prominent
              ? Theme.of(context).textTheme.titleLarge
              : Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 2),
        Text(
          track.artistNames,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.xSmall),
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

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xLarge),
      child: Column(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(
              Icons.queue_music_rounded,
              color: AppColors.purpleLight,
            ),
          ),
          const SizedBox(height: AppSpacing.medium),
          Text(
            'The queue is empty.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xSmall),
          Text(
            'Search for a track to get the music started.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
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
