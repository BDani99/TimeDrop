import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/haptics/app_haptics.dart';
import '../../core/theme/app_typography.dart';

/// Live `DD:HH:MM:SS`-ish countdown to [target]. Shows "Ready to open" once
/// the target has passed instead of a negative countdown.
class CountdownTimer extends StatefulWidget {
  const CountdownTimer({super.key, required this.target});

  final DateTime target;

  @override
  State<CountdownTimer> createState() => _CountdownTimerState();
}

class _CountdownTimerState extends State<CountdownTimer> {
  Timer? _timer;
  late Duration _remaining;
  bool _didFireCompleteHaptic = false;

  @override
  void initState() {
    super.initState();
    _remaining = widget.target.difference(DateTime.now());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final next = widget.target.difference(DateTime.now());
      if (!next.isNegative && next.inSeconds <= 1 && !_didFireCompleteHaptic) {
        _didFireCompleteHaptic = true;
        AppHaptics.countdownComplete();
      }
      setState(() => _remaining = next);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_remaining.isNegative) {
      return Text('Ready to open', style: AppTypography.headlineMd);
    }

    final days = _remaining.inDays;
    final hours = _remaining.inHours % 24;
    final minutes = _remaining.inMinutes % 60;
    final seconds = _remaining.inSeconds % 60;

    final text = days > 0
        ? '${_two(days)}:${_two(hours)}:${_two(minutes)}:${_two(seconds)}'
        : '${_two(hours)}:${_two(minutes)}:${_two(seconds)}';

    return Text(text, style: AppTypography.headlineMd);
  }

  String _two(int n) => n.toString().padLeft(2, '0');
}
