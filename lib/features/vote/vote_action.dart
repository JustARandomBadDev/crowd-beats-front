import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
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
      return Semantics(
        label: 'Submitting vote',
        liveRegion: true,
        child: const SizedBox.square(
          dimension: 46,
          child: Padding(
            padding: EdgeInsets.all(11),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    final completed =
        action?.phase == VotePhase.accepted ||
        action?.phase == VotePhase.alreadyVoted;
    final inactive = action?.phase == VotePhase.trackInactive;
    final failed = action != null && !completed && !inactive;
    final foreground = completed
        ? AppColors.success
        : failed
        ? AppColors.error
        : AppColors.purpleLight;
    return IconButton.outlined(
      tooltip: completed ? 'Voted for $trackTitle' : 'Vote for $trackTitle',
      onPressed: completed || inactive ? null : onVote,
      style: IconButton.styleFrom(
        fixedSize: const Size.square(46),
        foregroundColor: foreground,
        disabledForegroundColor: completed
            ? AppColors.success
            : AppColors.textMuted,
        backgroundColor: completed
            ? AppColors.successSurface
            : AppColors.surface,
        disabledBackgroundColor: completed
            ? AppColors.successSurface
            : AppColors.surface,
        side: BorderSide(
          color: completed
              ? AppColors.success.withValues(alpha: 0.55)
              : inactive
              ? AppColors.border
              : foreground.withValues(alpha: 0.55),
        ),
      ),
      icon: Icon(
        completed
            ? Icons.check_rounded
            : inactive
            ? Icons.block_rounded
            : Icons.arrow_upward_rounded,
      ),
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
    final (icon, color) = switch (value.phase) {
      VotePhase.accepted => (
        Icons.check_circle_outline_rounded,
        AppColors.success,
      ),
      VotePhase.alreadyVoted => (
        Icons.info_outline_rounded,
        AppColors.purpleLight,
      ),
      VotePhase.limitReached || VotePhase.trackInactive => (
        Icons.warning_amber_rounded,
        AppColors.warning,
      ),
      VotePhase.error => (Icons.error_outline_rounded, AppColors.error),
      VotePhase.submitting => (Icons.sync_rounded, AppColors.purpleLight),
    };
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.small),
      child: Semantics(
        liveRegion: true,
        child: Row(
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: AppSpacing.small),
            Expanded(
              child: Text(
                value.message,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
