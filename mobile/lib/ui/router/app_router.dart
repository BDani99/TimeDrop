import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/share_link_parser.dart';
import '../../providers/auth_provider.dart';
import '../../providers/capsule_provider.dart';
import '../../providers/payment_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/clipboard_service.dart';
import '../../services/system_settings_service.dart';
import '../screens/home_screen.dart';
import '../screens/onboarding_screen.dart';
import '../screens/radar_screen.dart';
import '../screens/splash_screen.dart';
import '../widgets/app_snackbar.dart';

/// Splash → bootstrap (auth + settings + system config + persisted premium)
/// → clipboard check → RadarScreen (valid link), OnboardingScreen (fresh new
/// user), or HomeScreen.
class MainRouter extends StatefulWidget {
  const MainRouter({super.key});

  @override
  State<MainRouter> createState() => _MainRouterState();
}

class _MainRouterState extends State<MainRouter> with WidgetsBindingObserver {
  bool _bootstrapped = false;
  bool _onboardingCompleted = false;
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
    // Capture providers up front so we never touch `context` across an
    // async gap below.
    final auth = context.read<AuthProvider>();
    final settings = context.read<SettingsProvider>();
    final payment = context.read<PaymentProvider>();
    final capsule = context.read<CapsuleProvider>();

    try {
      await auth.bootstrap();
      final userId = auth.userId;

      if (userId != null) {
        // Resume any background uploads stranded by a previous app kill. Fire-
        // and-forget so it never blocks app start; it re-drives from the
        // persisted queue using the now-restored auth session.
        unawaited(capsule.resumePendingUploads());

        // Load per-account settings (onboarding + free drop state). Kept
        // non-fatal so a transient settings error doesn't block the app.
        try {
          await settings.load(userId);
        } catch (e) {
          if (mounted) AppSnackbar.showError(context, e);
        }
      }
      // Runtime config + persisted premium are both best-effort.
      await SystemSettingsService.fetch();
      await payment.loadPersistedPremium();

      final link = await ClipboardService.checkClipboardForShareLink();
      if (!mounted) return;
      setState(() {
        _pendingLink = link;
        _onboardingCompleted = settings.onboardingCompleted;
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
      // Recipient: show their drop first. Onboarding (for new users) fires
      // when they leave the radar/video via `enterAppAfterRecipient`.
      return RadarScreen(
        key: ValueKey('radar-${link.shareId}'),
        shareId: link.shareId,
        encryptionKey: link.encryptionKey,
        fromName: link.fromName,
      );
    }

    if (!_onboardingCompleted) return const OnboardingScreen();
    return const HomeScreen();
  }
}

/// Called when a recipient closes the map/video of a drop they received.
/// Stops the GPS stream and enters the main app — routing a brand-new user
/// through onboarding first (per the "onboarding on close" requirement),
/// otherwise straight to Home.
void enterAppAfterRecipient(BuildContext context) {
  context.read<CapsuleProvider>().stopWatchingPosition();
  final onboardingDone = context.read<SettingsProvider>().onboardingCompleted;
  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(
      builder: (_) => onboardingDone ? const HomeScreen() : const OnboardingScreen(),
    ),
    (route) => false,
  );
}

/// Convenience for screens that finish the Radar flow and want to stop the
/// GPS stream without re-triggering the clipboard link.
void clearPendingRadarLink(BuildContext context) {
  context.read<CapsuleProvider>().stopWatchingPosition();
}
