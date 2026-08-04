import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../models/received_capsule_model.dart';
import '../widgets/glass/glass_panel.dart';
import '../widgets/primary_button.dart';

class MemoryTimelineEvent {
  const MemoryTimelineEvent({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;
}

/// Dedicated detail view with memory timeline for a received capsule.
class MemoryDetailScreen extends StatelessWidget {
  const MemoryDetailScreen({
    super.key,
    required this.item,
    required this.onPrimaryAction,
    required this.primaryLabel,
    this.savedForever = false,
  });

  final ReceivedCapsuleModel item;
  final VoidCallback onPrimaryAction;
  final String primaryLabel;
  final bool savedForever;

  static String _format(DateTime? dt) {
    if (dt == null) return '—';
    final local = dt.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  List<MemoryTimelineEvent> _events() {
    final waitingEnd = item.unlockedAt ?? (item.isUnlockTimeReached ? item.unlockTime : null);
    final waitingDuration = waitingEnd != null
        ? waitingEnd.difference(item.firstSeenAt)
        : DateTime.now().difference(item.firstSeenAt);

    return [
      MemoryTimelineEvent(
        title: 'Created',
        subtitle: _format(item.capsuleCreatedAt),
        icon: Icons.videocam_outlined,
      ),
      MemoryTimelineEvent(
        title: 'Added to vault',
        subtitle: _format(item.firstSeenAt),
        icon: Icons.inbox_outlined,
      ),
      MemoryTimelineEvent(
        title: 'Waiting',
        // Anything under a day used to render as a flat "0 days".
        subtitle: waitingDuration.inDays < 1
            ? 'Less than a day'
            : '${waitingDuration.inDays} '
                '${waitingDuration.inDays == 1 ? 'day' : 'days'}',
        icon: Icons.hourglass_empty,
      ),
      MemoryTimelineEvent(
        title: 'Unlocked',
        subtitle: item.unlockedAt != null
            ? '${_format(item.unlockedAt)}${item.city != null ? ' · ${item.city}' : ''}'
            : (item.isUnlockTimeReached ? 'Ready' : 'Pending'),
        icon: Icons.explore_outlined,
      ),
      MemoryTimelineEvent(
        title: 'Watched',
        subtitle: _format(item.viewedAt),
        icon: Icons.play_circle_outline,
      ),
      if (savedForever)
        const MemoryTimelineEvent(
          title: 'Kept',
          subtitle: 'Key backed up to your account',
          icon: Icons.favorite,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final events = _events();
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: Text(item.senderLabel)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.containerMargin),
        children: [
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Memory timeline', style: AppTypography.headlineMd),
                const SizedBox(height: AppSpacing.md),
                for (var i = 0; i < events.length; i++) ...[
                  _TimelineRow(event: events[i], isLast: i == events.length - 1, index: i),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(label: primaryLabel, onPressed: onPrimaryAction),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.event, required this.isLast, required this.index});

  final MemoryTimelineEvent event;
  final bool isLast;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: AppRadii.smRadius,
              ),
              child: Icon(event.icon, size: 18, color: AppColors.primary),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 36,
                color: AppColors.outlineVariant,
              ),
          ],
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.title, style: AppTypography.labelMd.copyWith(color: AppColors.onSurface)),
                const SizedBox(height: 2),
                Text(
                  event.subtitle,
                  style: AppTypography.labelSm.copyWith(color: AppColors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ],
    )
        .animate()
        .fadeIn(duration: 380.ms, delay: Duration(milliseconds: 60 + index * 80))
        .slideX(begin: 0.06, end: 0, duration: 380.ms,
            delay: Duration(milliseconds: 60 + index * 80),
            curve: Curves.easeOutCubic);
  }
}
