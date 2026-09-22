import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/track.dart';
import '../session/session_controller.dart';
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _queryController,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: 'Song, artist, or album',
                suffixIcon: IconButton(
                  tooltip: 'Search',
                  onPressed: () => controller.search(_queryController.text),
                  icon: const Icon(Icons.search),
                ),
              ),
              onSubmitted: controller.search,
            ),
          ),
          if (state.proposalMessage case final message?)
            _FeedbackBanner(
              message: message,
              isError: state.proposalPhase == ProposalPhase.error,
            ),
          Expanded(
            child: _SearchBody(state: state, controller: controller),
          ),
        ],
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
        return Center(
          child: Text(state.searchMessage ?? 'Search for a track to propose.'),
        );
      case SearchPhase.loading:
        return const Center(child: CircularProgressIndicator());
      case SearchPhase.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  state.searchMessage ?? 'Could not search right now.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: controller.retrySearch,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        );
      case SearchPhase.results:
        if (state.results.isEmpty) {
          return const Center(child: Text('No tracks found.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          itemCount: state.results.length,
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
      child: ListTile(
        leading: _Artwork(url: track.imageUrl),
        title: Text(track.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${track.artistNames}\n${track.albumName} · ${_duration(track.durationMs)}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: true,
        trailing: proposing
            ? const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                tooltip: 'Propose ${track.title}',
                onPressed: proposalBusy ? null : onPropose,
                icon: const Icon(Icons.add_circle_outline),
              ),
        onTap: proposalBusy ? null : onPropose,
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.url});

  final String url;

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
        child: url.isEmpty
            ? placeholder
            : Image.network(
                url,
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

class _FeedbackBanner extends StatelessWidget {
  const _FeedbackBanner({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: isError ? colors.errorContainer : colors.primaryContainer,
      padding: const EdgeInsets.all(12),
      child: Text(message),
    );
  }
}

String _duration(int milliseconds) {
  final totalSeconds = milliseconds ~/ 1000;
  final minutes = totalSeconds ~/ 60;
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
