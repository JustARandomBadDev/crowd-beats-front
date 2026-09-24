import 'package:flutter/material.dart';

import 'vote_controller.dart';

class VoteButton extends StatelessWidget {
  const VoteButton({
    required this.trackTitle,
    required this.action,
    required this.onVote,
    super.key,
  });

  final String trackTitle;
  final TrackVoteState? action;
  final VoidCallback onVote;

  @override
  Widget build(BuildContext context) {
    if (action?.submitting == true) {
      return const SizedBox.square(
        dimension: 40,
        child: Padding(
          padding: EdgeInsets.all(8),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final completed =
        action?.phase == VotePhase.accepted ||
        action?.phase == VotePhase.alreadyVoted;
    final inactive = action?.phase == VotePhase.trackInactive;
    return IconButton(
      tooltip: completed ? 'Voted for $trackTitle' : 'Vote for $trackTitle',
      onPressed: completed || inactive ? null : onVote,
      icon: Icon(completed ? Icons.check_circle : Icons.thumb_up_outlined),
    );
  }
}

class VoteFeedback extends StatelessWidget {
  const VoteFeedback({required this.action, super.key});

  final TrackVoteState? action;

  @override
  Widget build(BuildContext context) {
    final value = action;
    if (value == null || value.submitting) return const SizedBox.shrink();
    final isSuccess = value.phase == VotePhase.accepted;
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        value.message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: isSuccess ? colors.primary : colors.error,
        ),
      ),
    );
  }
}
