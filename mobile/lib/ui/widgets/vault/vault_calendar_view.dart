import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../models/received_capsule_model.dart';
import '../../../services/media_cache_service.dart';

/// Calendar view: a month grid at the top (dots on days that have memories),
/// then — when a day is tapped — a journaling-style card list below showing
/// the full preview (thumbnail, note excerpt, photo/video badge).
class VaultCalendarView extends StatefulWidget {
  const VaultCalendarView({
    super.key,
    required this.items,
    required this.onSelect,
  });

  final List<ReceivedCapsuleModel> items;
  final void Function(ReceivedCapsuleModel item) onSelect;

  @override
  State<VaultCalendarView> createState() => _VaultCalendarViewState();
}

class _VaultCalendarViewState extends State<VaultCalendarView> {
  late DateTime _focusedMonth;
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    final byDay = _byDay;
    // Focus on the month of the most-recent memory (not necessarily today).
    final latestDay = byDay.keys.isNotEmpty
        ? byDay.keys.reduce((a, b) => a.isAfter(b) ? a : b)
        : DateTime.now();
    _focusedMonth = DateTime(latestDay.year, latestDay.month);
    // Pre-select the most recent day that has memories.
    _selectedDay = byDay.containsKey(latestDay) ? latestDay : null;
  }

  Map<DateTime, List<ReceivedCapsuleModel>> get _byDay {
    final map = <DateTime, List<ReceivedCapsuleModel>>{};
    for (final item in widget.items.where((c) => c.isOpened)) {
      // Group by the day the capsule was *created* (recorded), not when it
      // was unlocked or viewed — this mirrors how a journal works.
      final raw = item.capsuleCreatedAt ?? item.unlockTime;
      map.putIfAbsent(_dayKey(raw), () => []).add(item);
    }
    return map;
  }

  DateTime _dayKey(DateTime dt) {
    final l = dt.toLocal();
    return DateTime(l.year, l.month, l.day);
  }

  void _shiftMonth(int delta) => setState(() {
        _focusedMonth =
            DateTime(_focusedMonth.year, _focusedMonth.month + delta);
        _selectedDay = null;
      });

  @override
  Widget build(BuildContext context) {
    final byDay = _byDay;
    final daysInMonth =
        DateUtils.getDaysInMonth(_focusedMonth.year, _focusedMonth.month);
    // weekday: Mon=1 … Sun=7. We want Mon at col 0.
    final firstWeekday =
        DateTime(_focusedMonth.year, _focusedMonth.month, 1).weekday;
    final blanks = firstWeekday - 1;

    final selectedItems =
        _selectedDay == null ? const <ReceivedCapsuleModel>[] : (byDay[_selectedDay!] ?? const []);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.containerMargin),
      children: [
        // ── Month header ─────────────────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _NavButton(
              icon: Icons.chevron_left,
              onTap: () => _shiftMonth(-1),
            ),
            Text(
              '${_monthName(_focusedMonth.month)} ${_focusedMonth.year}',
              style: AppTypography.headlineMd,
            ),
            _NavButton(
              icon: Icons.chevron_right,
              onTap: () => _shiftMonth(1),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),

        // ── Weekday labels ────────────────────────────────────────────────────
        Row(
          children: ['M', 'T', 'W', 'T', 'F', 'S', 'S']
              .map(
                (l) => Expanded(
                  child: Center(
                    child: Text(
                      l,
                      style: AppTypography.labelSm
                          .copyWith(color: AppColors.onSurfaceVariant),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: AppSpacing.xs),

        // ── Day grid ──────────────────────────────────────────────────────────
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 2,
          ),
          itemCount: blanks + daysInMonth,
          itemBuilder: (context, index) {
            if (index < blanks) return const SizedBox.shrink();
            final day = index - blanks + 1;
            final date =
                DateTime(_focusedMonth.year, _focusedMonth.month, day);
            final hasEvent = byDay.containsKey(date);
            final isSelected = _selectedDay == date;
            final isToday = DateUtils.isSameDay(date, DateTime.now());

            return InkWell(
              onTap: hasEvent
                  ? () => setState(() => _selectedDay = date)
                  : null,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                margin: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary
                      : isToday
                          ? AppColors.primaryContainer
                          : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$day',
                      style: AppTypography.labelMd.copyWith(
                        color: isSelected
                            ? AppColors.onPrimary
                            : isToday
                                ? AppColors.onPrimaryContainer
                                : AppColors.onSurface,
                        fontSize: 13,
                      ),
                    ),
                    if (hasEvent) ...[
                      const SizedBox(height: 2),
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected
                              ? AppColors.onPrimary.withValues(alpha: 0.8)
                              : AppColors.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),

        // ── Divider ───────────────────────────────────────────────────────────
        const SizedBox(height: AppSpacing.lg),

        if (_selectedDay != null && selectedItems.isNotEmpty) ...[
          // Date header like "OCTOBER 11TH"
          Center(
            child: Text(
              _dayHeader(_selectedDay!),
              style: AppTypography.labelMd.copyWith(
                color: AppColors.onSurfaceVariant,
                letterSpacing: 1.6,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final item in selectedItems) ...[
            _MemoryCard(item: item, onTap: () => widget.onSelect(item)),
            const SizedBox(height: AppSpacing.sm),
          ],
        ] else if (_selectedDay != null && selectedItems.isEmpty) ...[
          Center(
            child: Text(
              'No memories on this day.',
              style: AppTypography.bodyMd
                  .copyWith(color: AppColors.onSurfaceVariant),
            ),
          ),
        ] else ...[
          Center(
            child: Text(
              'Tap a day to see its memories.',
              style: AppTypography.bodyMd
                  .copyWith(color: AppColors.onSurfaceVariant),
            ),
          ),
        ],
      ],
    );
  }

  String _monthName(int m) => const [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December',
      ][m - 1];

  String _dayHeader(DateTime d) {
    final m = _monthName(d.month).toUpperCase();
    final day = d.day;
    final suffix = _ordinal(day);
    return '$m $day$suffix';
  }

  String _ordinal(int n) {
    if (n >= 11 && n <= 13) return 'TH';
    return switch (n % 10) {
      1 => 'ST',
      2 => 'ND',
      3 => 'RD',
      _ => 'TH',
    };
  }
}

// ── Simple nav button ─────────────────────────────────────────────────────────

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: Icon(icon, color: AppColors.onSurfaceVariant),
      ),
    );
  }
}

// ── Memory card (journaling style) ───────────────────────────────────────────

class _MemoryCard extends StatefulWidget {
  const _MemoryCard({required this.item, required this.onTap});

  final ReceivedCapsuleModel item;
  final VoidCallback onTap;

  @override
  State<_MemoryCard> createState() => _MemoryCardState();
}

class _MemoryCardState extends State<_MemoryCard> {
  static const _thumbSize = 80.0;

  // Cached once so FutureBuilder doesn't restart on every rebuild.
  late final Future<_CardData> _dataFuture = _loadData();

  Future<_CardData> _loadData() async {
    final cover = await MediaCacheService.coverPhoto(widget.item.capsuleId);
    final note = await MediaCacheService.noteFor(widget.item.capsuleId);
    final meta = await MediaCacheService.get(widget.item.capsuleId);
    return _CardData(
      cover: cover,
      note: note,
      photoCount: meta?.photos.length ?? 0,
    );
  }

  String _title() {
    final item = widget.item;
    if (item.fromName != null && item.fromName!.isNotEmpty) {
      return 'From ${item.fromName}';
    }
    if (item.city != null && item.city!.isNotEmpty) return item.city!;
    final d = (item.capsuleCreatedAt ?? item.unlockTime).toLocal();
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: AppRadii.mdRadius,
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: AppRadii.mdRadius,
          border: Border.all(color: AppColors.outlineVariant),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.md - 1),
          child: FutureBuilder<_CardData>(
            future: _dataFuture,
            builder: (context, snap) {
              final data = snap.data ?? const _CardData();
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Thumbnail: fixed square
                  SizedBox(
                    width: _thumbSize,
                    height: _thumbSize,
                    child: _Thumb(bytes: data.cover, width: _thumbSize),
                  ),

                  // Content
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _title(),
                            style: AppTypography.labelMd
                                .copyWith(color: AppColors.onSurface, fontSize: 15),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (data.note != null && data.note!.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              data.note!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.labelSm
                                  .copyWith(color: AppColors.onSurfaceVariant),
                            ),
                          ],
                          const SizedBox(height: 8),
                          _Badge(photoCount: data.photoCount),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CardData {
  const _CardData({this.cover, this.note, this.photoCount = 0});
  final Uint8List? cover;
  final String? note;
  final int photoCount;
}

// ── Thumbnail square ─────────────────────────────────────────────────────────

class _Thumb extends StatelessWidget {
  const _Thumb({required this.bytes, required this.width});
  final Uint8List? bytes;
  final double width;

  @override
  Widget build(BuildContext context) {
    // The thumb fills the full height of the card (set by IntrinsicHeight /
    // CrossAxisAlignment.stretch in the parent Row), with a fixed width.
    return SizedBox(
      width: width,
      child: bytes != null
          ? Image.memory(
              bytes!,
              width: width,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              // Ensures the image fills the stretched height without gaps.
              alignment: Alignment.center,
            )
          : Container(
              color: AppColors.surfaceContainer,
              alignment: Alignment.center,
              child: const Icon(
                Icons.play_circle_outline,
                color: AppColors.onSurfaceVariant,
                size: 28,
              ),
            ),
    );
  }
}

// ── Footer badge ──────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  const _Badge({required this.photoCount});
  final int photoCount;

  @override
  Widget build(BuildContext context) {
    final hasPhotos = photoCount > 0;
    return Row(
      children: [
        Icon(
          hasPhotos ? Icons.photo_library_outlined : Icons.videocam_outlined,
          size: 13,
          color: AppColors.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Text(
          hasPhotos
              ? '$photoCount ${photoCount == 1 ? 'Photo' : 'Photos'}'
              : 'Video',
          style: AppTypography.labelSm.copyWith(
            color: AppColors.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
