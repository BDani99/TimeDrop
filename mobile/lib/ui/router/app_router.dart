import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/share_link_parser.dart';
import '../../providers/auth_provider.dart';
import '../../providers/capsule_provider.dart';
import '../../services/clipboard_service.dart';
import '../screens/home_screen.dart';
import '../screens/radar_screen.dart';
import '../screens/splash_screen.dart';
import '../widgets/app_snackbar.dart';

/// Splash → clipboard check → RadarScreen (valid TimeDrop link found) or
/// HomeScreen (no link) — per terv.md Sprint 0's MainRouter spec.
class MainRouter extends StatefulWidget {
  const MainRouter({super.key});

  @override
  State<MainRouter> createState() => _MainRouterState();
}

class _MainRouterState extends State<MainRouter> with WidgetsBindingObserver {
  bool _bootstrapped = false;
  ShareLinkModel? _pendingLink;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _bootstrapped) {
      _checkClipboardInBackground();
    }
  }

  Future<void> _bootstrap() async {
    try {
      await context.read<AuthProvider>().bootstrap();
      final link = await ClipboardService.checkClipboardForShareLink();
      if (!mounted) return;
      setState(() {
        _pendingLink = link;
        _bootstrapped = true;
      });
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.showError(context, e);
      setState(() => _bootstrapped = true);
    }
  }

  Future<void> _checkClipboardInBackground() async {
    final link = await ClipboardService.checkClipboardForShareLink();
    if (link == null || !mounted) return;
    setState(() => _pendingLink = link);
  }

  @override
  Widget build(BuildContext context) {
    if (!_bootstrapped) return const SplashScreen();

    final link = _pendingLink;
    if (link != null) {
      return RadarScreen(
        key: ValueKey('radar-${link.shareId}'),
        shareId: link.shareId,
        encryptionKey: link.encryptionKey,
      );
    }
    return const HomeScreen();
  }
}

/// Convenience for screens that finish the Radar flow and want to return to
/// a clean Home without re-triggering the clipboard link.
void clearPendingRadarLink(BuildContext context) {
  context.read<CapsuleProvider>().stopWatchingPosition();
}
