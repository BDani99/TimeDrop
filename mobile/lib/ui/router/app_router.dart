import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/share_link_parser.dart';
import '../../providers/auth_provider.dart';
import '../../providers/capsule_provider.dart';
import '../../providers/payment_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/clipboard_service.dart';
import '../../services/presented_shares_service.dart';
import '../../services/system_settings_service.dart';
import '../screens/gift_received_screen.dart';
import '../screens/home_screen.dart';
import '../screens/onboarding_screen.dart';
import '../screens/splash_screen.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/navigation/spring_page_route.dart';

/// Splash → bootstrap (auth + settings + system config + persisted premium)
/// → clipboard check → GiftReceivedScreen (first time only), OnboardingScreen,
/// or HomeScreen.
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
    final auth = context.read<AuthProvider>();
    final settings = context.read<SettingsProvider>();
    final payment = context.read<PaymentProvider>();
    final capsule = context.read<CapsuleProvider>();

    try {
      await auth.bootstrap();
      unawaited(settings.loadLocalPrefs());
      final userId = auth.userId;

      if (userId != null) {
        unawaited(capsule.resumePendingUploads());
        unawaited(capsule.reconcileStuckCapsules(userId));
        try {
          await settings.load(userId);
        } catch (e) {
          if (mounted) AppSnackbar.showError(context, e);
        }
      }
      await SystemSettingsService.fetch();
      await payment.loadPersistedPremium();

      final link = await _firstTimeClipboardLink();
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

  /// Only returns a link the first time this shareId is seen — subsequent
  /// launches with the same clipboard content go straight to Home.
  Future<ShareLinkModel?> _firstTimeClipboardLink() async {
    final link = await ClipboardService.checkClipboardForShareLink();
    if (link == null) return null;
    if (await PresentedSharesService.hasPresented(link.shareId)) return null;
    return link;
  }

  Future<void> _checkClipboardInBackground() async {
    final link = await _firstTimeClipboardLink();
    if (link == null || !mounted) return;
    setState(() => _pendingLink = link);
  }

  @override
  Widget build(BuildContext context) {
    if (!_bootstrapped) return const SplashScreen();

    final link = _pendingLink;
    if (link != null) {
      return GiftReceivedScreen(
        key: ValueKey('gift-${link.shareId}'),
        shareId: link.shareId,
        encryptionKey: link.encryptionKey,
        fromName: link.fromName,
      );
    }

    if (!_onboardingCompleted) return const OnboardingScreen();
    return const HomeScreen();
  }
}

/// Called when a recipient closes the gift/radar/video of a drop they received.
void enterAppAfterRecipient(BuildContext context) {
  context.read<CapsuleProvider>().stopWatchingPosition();
  final onboardingDone = context.read<SettingsProvider>().onboardingCompleted;
  Navigator.pushAndRemoveUntil(
    context,
    SpringPageRoute(
      page: onboardingDone ? const HomeScreen() : const OnboardingScreen(),
    ),
    (route) => false,
  );
}

void clearPendingRadarLink(BuildContext context) {
  context.read<CapsuleProvider>().stopWatchingPosition();
}
