import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/share_link_parser.dart';
import '../../providers/auth_provider.dart';
import '../../providers/capsule_provider.dart';
import '../../providers/drop_balance_provider.dart';
import '../../providers/payment_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/system_settings_service.dart';
import '../screens/gift_received_screen.dart';
import '../screens/home_screen.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../screens/splash_screen.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/navigation/spring_page_route.dart';

/// Splash → bootstrap (auth + settings + system config + drop balance)
/// → GiftReceivedScreen if a share link brought us here, else OnboardingScreen
/// or HomeScreen.
///
/// Share links arrive as OS deep links (Universal Links / App Links), not by
/// reading the clipboard. The old approach worked, but it meant peeking at the
/// clipboard on every foreground — and it routed the user through a browser
/// page to get back into the app.
class MainRouter extends StatefulWidget {
  const MainRouter({super.key});

  /// Forgets the link that brought the user here, so the router falls back to
  /// Home/Onboarding and a second tap on the same link opens it again.
  static void clearPendingLink(BuildContext context) {
    context.findAncestorStateOfType<MainRouterState>()?.clearPendingLink();
  }

  @override
  State<MainRouter> createState() => MainRouterState();
}

class MainRouterState extends State<MainRouter> {
  bool _bootstrapped = false;
  bool _onboardingCompleted = false;

  /// A complete link, ready to open.
  ShareLinkModel? _pendingLink;

  /// Our link, but the decryption key never arrived — see [IncompleteShareLink].
  IncompleteShareLink? _pendingIncompleteLink;

  StreamSubscription<String?>? _userIdSub;
  StreamSubscription<Uri>? _linkSub;
  final AppLinks _appLinks = AppLinks();

  @override
  void initState() {
    super.initState();
    // Sign-out, account deletion and account linking all swap the signed-in
    // user underneath us. Everything cached per-user has to be reloaded, or
    // the previous account's settings keep showing.
    _userIdSub = context.read<AuthProvider>().userIdChanges.listen(_onUserChanged);
    // Links tapped while the app is already running. The cold-start link is
    // picked up inside _bootstrap so it lands in the same setState.
    _linkSub = _appLinks.uriLinkStream.listen(
      _onDeepLink,
      onError: (Object e) => debugPrint('Deep link stream error: $e'),
    );
    _bootstrap();
  }

  @override
  void dispose() {
    _userIdSub?.cancel();
    _linkSub?.cancel();
    super.dispose();
  }

  /// Routes a deep link, whether it carries a usable key or not.
  void _applyLink(Object? parsed) {
    if (parsed is ShareLinkModel) {
      setState(() {
        _pendingLink = parsed;
        _pendingIncompleteLink = null;
      });
    } else if (parsed is IncompleteShareLink) {
      setState(() {
        _pendingLink = null;
        _pendingIncompleteLink = parsed;
      });
    }
    // Anything else is not a TimeDrop link — leave the current screen alone.
  }

  void _onDeepLink(Uri uri) {
    if (!mounted) return;
    _applyLink(ShareLinkParser.parseParts(uri.toString()));
  }

  Future<void> _onUserChanged(String? userId) async {
    if (!_bootstrapped || !mounted) return;
    final settings = context.read<SettingsProvider>();
    final drops = context.read<DropBalanceProvider>();

    final payment = context.read<PaymentProvider>();

    // Signed out entirely: drop the previous account's balance so the UI never
    // shows one user's drops to another.
    drops.clear();
    if (userId == null) {
      unawaited(payment.detachUser());
      return;
    }

    unawaited(payment.attachUser(userId));
    unawaited(drops.refresh());
    unawaited(context.read<AuthProvider>().refreshReviewerStatus());
    try {
      await settings.load(userId);
    } catch (e) {
      if (mounted) AppSnackbar.showError(context, e);
      return;
    }
    if (!mounted) return;
    setState(() => _onboardingCompleted = settings.onboardingCompleted);
  }

  Future<void> _bootstrap() async {
    final auth = context.read<AuthProvider>();
    final settings = context.read<SettingsProvider>();
    final payment = context.read<PaymentProvider>();
    final capsule = context.read<CapsuleProvider>();
    final drops = context.read<DropBalanceProvider>();

    try {
      await auth.bootstrap();
      // Awaited, not fire-and-forget: it carries the device-scoped onboarding
      // flag that the routing decision below reads. Racing it would replay the
      // whole flow after every reinstall.
      await settings.loadLocalPrefs();
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
      if (userId != null) {
        // Purchases.logIn must come after PaymentProvider.initialize (done in
        // main.dart) and before any purchase, or the webhook cannot map the
        // purchase back to this account.
        await payment.attachUser(userId);
        await drops.refresh();
        // Off the critical path: a reviewer's flag only affects gating, and a
        // slow round trip should not hold up the splash screen.
        unawaited(auth.refreshReviewerStatus());
      }

      // A link that launched the app from cold. Read here so it lands in the
      // same setState as the rest of the bootstrap — no intermediate frame
      // where Home flashes before the gift screen replaces it.
      Object? initial;
      try {
        final uri = await _appLinks.getInitialLink();
        if (uri != null) initial = ShareLinkParser.parseParts(uri.toString());
      } catch (e) {
        debugPrint('Could not read the launch link: $e');
      }

      if (!mounted) return;
      setState(() {
        if (initial is ShareLinkModel) {
          _pendingLink = initial;
        } else if (initial is IncompleteShareLink) {
          _pendingIncompleteLink = initial;
        }
        _onboardingCompleted = settings.onboardingCompleted;
        _bootstrapped = true;
      });
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.showError(context, e);
      setState(() => _bootstrapped = true);
    }
  }

  /// Called when the user leaves the gift screen, so tapping the same link
  /// again re-opens it instead of being swallowed as "already showing".
  void clearPendingLink() {
    if (_pendingLink == null && _pendingIncompleteLink == null) return;
    setState(() {
      _pendingLink = null;
      _pendingIncompleteLink = null;
    });
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

    final incomplete = _pendingIncompleteLink;
    if (incomplete != null) {
      return GiftReceivedScreen(
        key: ValueKey('gift-incomplete-${incomplete.shareId}'),
        shareId: incomplete.shareId,
        // No key: the screen asks for the full link rather than failing.
        encryptionKey: null,
        fromName: incomplete.fromName,
      );
    }

    if (!_onboardingCompleted) return const OnboardingScreen();
    return const HomeScreen();
  }
}

/// Called when a recipient closes the gift/radar/video of a drop they received.
///
/// [landOnVault] is set when they actually *finished* a memory: the app then
/// opens the Vault so the thing they just watched is waiting for them, rather
/// than dropping them on a Home screen that says nothing about it. Someone who
/// merely backed out of the radar gets the normal Home landing.
///
/// When onboarding has not been done yet the flag rides along through
/// `OnboardingScreen` → `PaywallScreen` → `HomeScreen`, because those screens
/// each replace the whole stack and there is nothing left behind to return to.
void enterAppAfterRecipient(BuildContext context, {bool landOnVault = false}) {
  context.read<CapsuleProvider>().stopWatchingPosition();
  // Release the link, or the router would still be showing the gift screen
  // underneath the page we are about to install.
  MainRouter.clearPendingLink(context);
  final onboardingDone = context.read<SettingsProvider>().onboardingCompleted;
  Navigator.pushAndRemoveUntil(
    context,
    SpringPageRoute(
      page: onboardingDone
          ? HomeScreen(openVaultOnStart: landOnVault)
          : OnboardingScreen(landOnVault: landOnVault),
    ),
    (route) => false,
  );
}

void clearPendingRadarLink(BuildContext context) {
  context.read<CapsuleProvider>().stopWatchingPosition();
}
