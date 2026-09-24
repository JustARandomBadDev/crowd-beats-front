import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../models/track.dart';
import '../room/room_controller.dart';
import '../session/session_controller.dart';
import '../vote/vote_action.dart';
import '../vote/vote_controller.dart';
import 'track_search_controller.dart';

class TrackSearchScreen extends ConsumerStatefulWidget {
  const TrackSearchScreen({required this.session, super.key});

  final TrackSearchSession session;

  @override
  ConsumerState<TrackSearchScreen> createState() => _TrackSearchScreenState();
}

class _TrackSearchScreenState extends ConsumerState<TrackSearchScreen> {
  final _queryController = TextEditingController();

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = trackSearchControllerProvider(widget.session);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final roomKey = RoomSessionKey(
      roomId: widget.session.roomId,
      token: widget.session.token,
    );
    final voteState = ref.watch(voteControllerProvider(roomKey));
    final voteController = ref.read(voteControllerProvider(roomKey).notifier);
    ref.listen(sessionControllerProvider, (_, next) {
      final active = next.active;
      if ((active?.roomId != widget.session.roomId ||
              active?.token != widget.session.token) &&
          mounted) {
        Navigator.of(context).maybePop();
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Search music')),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.large,
                AppSpacing.small,
                AppSpacing.large,
                AppSpacing.large,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Find the next track',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSpacing.xSmall),
                  Text(
                    'Search Spotify through CrowdBeats, then propose a result to this room.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.large),
                  TextField(
                    controller: _queryController,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Song, artist, or album',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: IconButton(
                        tooltip: 'Search',
                        onPressed: () =>
                            controller.search(_queryController.text),
                        icon: const Icon(Icons.arrow_forward_rounded),
                      ),
                    ),
                    onSubmitted: controller.search,
                  ),
                ],
              ),
            ),
            if (state.proposalMessage case final message?)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.large,
                  0,
                  AppSpacing.large,
                  AppSpacing.medium,
                ),
                child: _ProposalFeedback(
                  message: message,
                  phase: state.proposalPhase,
                ),
              ),
            if (state.proposal?.existingRoomTrack case final existing?)
              _DuplicateVoteAction(
                action: voteState.actionFor(existing.id),
                votesRemaining: voteState.votesRemaining,
                onVote: () => voteController.vote(existing.id),
              ),
            Expanded(
              child: _SearchBody(state: state, controller: controller),
            ),
          ],
        ),
      ),
    );
  }
}

class _DuplicateVoteAction extends StatelessWidget {
  const _DuplicateVoteAction({
    required this.action,
    required this.votesRemaining,
    required this.onVote,
  });

  final TrackVoteState? action;
  final int? votesRemaining;
  final VoidCallback onVote;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.large,
        0,
        AppSpacing.large,
        AppSpacing.medium,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.large),
        decoration: BoxDecoration(
          color: AppColors.surfaceStrong,
          borderRadius: BorderRadius.circular(AppRadii.medium),
          border: Border.all(color: AppColors.purpleMuted),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.queue_music_rounded,
                  color: AppColors.purpleLight,
                ),
                const SizedBox(width: AppSpacing.medium),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Already in the queue',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        'Vote for the existing track',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                VoteButton(
                  trackTitle: 'this track',
                  action: action,
                  onVote: onVote,
                ),
              ],
            ),
            VoteFeedback(action: action),
            if (votesRemaining case final remaining?) ...[
              const SizedBox(height: AppSpacing.small),
              AppStatusChip(
                label: remaining == 1
                    ? '1 personal vote remaining'
                    : '$remaining personal votes remaining',
                icon: Icons.how_to_vote_outlined,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SearchBody extends StatelessWidget {
  const _SearchBody({required this.state, required this.controller});

  final TrackSearchState state;
  final TrackSearchController controller;

  @override
  Widget build(BuildContext context) {
    switch (state.searchPhase) {
      case SearchPhase.initial:
        return _SearchPlaceholder(
          icon: Icons.library_music_outlined,
          title: 'Search the music catalog',
          message:
              state.searchMessage ?? 'Find a track to propose to the room.',
        );
      case SearchPhase.loading:
        return const AppLoadingState(label: 'Searching music…');
      case SearchPhase.error:
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xLarge),
            child: AppMessageCard(
              title: 'Search unavailable',
              message: state.searchMessage ?? 'Could not search right now.',
              tone: AppMessageTone.error,
              action: FilledButton.icon(
                onPressed: controller.retrySearch,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ),
          ),
        );
      case SearchPhase.results:
        if (state.results.isEmpty) {
          return const _SearchPlaceholder(
            icon: Icons.search_off_rounded,
            title: 'No tracks found',
            message: 'Try another title, artist, or album.',
          );
        }
        return ListView.separated(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.large,
            AppSpacing.xSmall,
            AppSpacing.large,
            AppSpacing.xLarge,
          ),
          itemCount: state.results.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.small),
          itemBuilder: (context, index) {
            final track = state.results[index];
            return _SearchResultTile(
              track: track,
              proposing: state.proposingSpotifyTrackId == track.spotifyTrackId,
              proposalBusy: state.proposing,
              onPropose: () => controller.propose(track),
            );
          },
        );
    }
  }
}

class _SearchPlaceholder extends StatelessWidget {
  const _SearchPlaceholder({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xLarge),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(icon, color: AppColors.purpleLight, size: 28),
            ),
            const SizedBox(height: AppSpacing.large),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xSmall),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({
    required this.track,
    required this.proposing,
    required this.proposalBusy,
    required this.onPropose,
  });

  final SpotifyTrackDto track;
  final bool proposing;
  final bool proposalBusy;
  final VoidCallback onPropose;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.medium),
        onTap: proposalBusy ? null : onPropose,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.medium),
          child: Row(
            children: [
              TrackArtwork(imageUrl: track.imageUrl, size: 58),
              const SizedBox(width: AppSpacing.medium),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.artistNames,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    Text(
                      '${track.albumName}  ·  ${_duration(track.durationMs)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.small),
              if (proposing)
                const SizedBox.square(
                  dimension: 44,
                  child: Padding(
                    padding: EdgeInsets.all(11),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                IconButton.filledTonal(
                  tooltip: 'Propose ${track.title}',
                  onPressed: proposalBusy ? null : onPropose,
                  icon: const Icon(Icons.add_rounded),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProposalFeedback extends StatelessWidget {
  const _ProposalFeedback({required this.message, required this.phase});

  final String message;
  final ProposalPhase phase;

  @override
  Widget build(BuildContext context) {
    final tone = switch (phase) {
      ProposalPhase.accepted => AppMessageTone.success,
      ProposalPhase.duplicate => AppMessageTone.neutral,
      ProposalPhase.error => AppMessageTone.error,
      ProposalPhase.idle || ProposalPhase.submitting => AppMessageTone.neutral,
    };
    return AppMessageCard(message: message, tone: tone, compact: true);
  }
}

String _duration(int milliseconds) {
  final totalSeconds = milliseconds ~/ 1000;
  final minutes = totalSeconds ~/ 60;
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
