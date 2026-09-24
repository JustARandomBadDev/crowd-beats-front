import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum AppMessageTone { neutral, success, warning, error }

class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({required this.label, this.trailing, super.key});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.medium,
      runSpacing: AppSpacing.small,
      children: [
        Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall,
        ),
        ?trailing,
      ],
    );
  }
}

class AppStatusChip extends StatelessWidget {
  const AppStatusChip({
    required this.label,
    this.icon,
    this.tone = AppMessageTone.neutral,
    super.key,
  });

  final String label;
  final IconData? icon;
  final AppMessageTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = _toneColors(tone);
    return Semantics(
      label: label,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.75,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colors.$1,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: colors.$2.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: colors.$2),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.$2,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppMessageCard extends StatelessWidget {
  const AppMessageCard({
    required this.message,
    this.title,
    this.action,
    this.icon,
    this.tone = AppMessageTone.neutral,
    this.compact = false,
    super.key,
  });

  final String message;
  final String? title;
  final Widget? action;
  final IconData? icon;
  final AppMessageTone tone;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = _toneColors(tone);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? AppSpacing.medium : AppSpacing.large),
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: Border.all(color: colors.$2.withValues(alpha: 0.38)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? _toneIcon(tone), size: 20, color: colors.$2),
          const SizedBox(width: AppSpacing.medium),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(title!, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xSmall),
                ],
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(height: AppSpacing.medium),
                  action!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TrackArtwork extends StatelessWidget {
  const TrackArtwork({
    required this.imageUrl,
    this.size = 56,
    this.radius = AppRadii.small,
    super.key,
  });

  final String imageUrl;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: AppColors.surface,
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          color: AppColors.textMuted,
          size: size * 0.38,
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox.square(
        dimension: size,
        child: imageUrl.isEmpty
            ? placeholder
            : Image.network(
                imageUrl,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : ColoredBox(
                        color: AppColors.surface,
                        child: Center(
                          child: SizedBox.square(
                            dimension: size * 0.28,
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                      ),
                errorBuilder: (context, error, stackTrace) => placeholder,
              ),
      ),
    );
  }
}

class AppLoadingState extends StatelessWidget {
  const AppLoadingState({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      liveRegion: true,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xLarge),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox.square(
                dimension: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(height: AppSpacing.large),
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}

(Color, Color) _toneColors(AppMessageTone tone) => switch (tone) {
  AppMessageTone.neutral => (AppColors.surface, AppColors.purpleLight),
  AppMessageTone.success => (AppColors.successSurface, AppColors.success),
  AppMessageTone.warning => (AppColors.warningSurface, AppColors.warning),
  AppMessageTone.error => (AppColors.errorSurface, AppColors.error),
};

IconData _toneIcon(AppMessageTone tone) => switch (tone) {
  AppMessageTone.neutral => Icons.info_outline_rounded,
  AppMessageTone.success => Icons.check_circle_outline_rounded,
  AppMessageTone.warning => Icons.sync_problem_rounded,
  AppMessageTone.error => Icons.error_outline_rounded,
};
