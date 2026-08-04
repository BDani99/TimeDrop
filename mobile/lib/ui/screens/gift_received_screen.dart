import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/name_format.dart';
import '../../core/utils/share_link_parser.dart';
import '../../models/capsule_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/supabase_service.dart';
import '../router/app_router.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/countdown_timer.dart';
import '../widgets/loading/skeleton_box.dart';
import '../widgets/navigation/spring_page_route.dart';
import '../widgets/primary_button.dart';
import 'radar_screen.dart';

/// First-touch receive experience: emotional intro + countdown (or Open now).
/// No map, radar, or media.
///
/// [encryptionKey] is null when the link reached us without its `#` fragment —
/// Android does not always deliver it with an App Link. The memory is still
/// recognised and tracked, but it cannot be opened, so the screen asks for the
/// full link instead of failing silently.
class GiftReceivedScreen extends StatefulWidget {
  const GiftReceivedScreen({
    super.key,
    required this.shareId,
    required this.encryptionKey,
    this.fromName,
  });

  final String shareId;
  final String? encryptionKey;
  final String? fromName;

  @override
  State<GiftReceivedScreen> createState() => _GiftReceivedScreenState();
}

class _GiftReceivedScreenState extends State<GiftReceivedScreen> {
  CapsuleModel? _capsule;
  bool _loading = true;
  bool _failed = false;

  /// Filled in from the widget, then possibly upgraded when the user pastes
  /// the full link on the "incomplete link" state.
  String? _encryptionKey;

  final TextEditingController _linkController = TextEditingController();
  bool _linkError = false;

  bool get _hasKey => _encryptionKey != null;

  @override
  void initState() {
    super.initState();
    _encryptionKey = widget.encryptionKey;
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _linkController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final userId = context.read<AuthProvider>().userId;
    try {
      if (userId == null) {
        throw const AuthException('You need to be signed in to receive this memory.');
      }

      final capsule = await SupabaseService.fetchCapsuleByShareId(widget.shareId);
      if (capsule == null) {
        throw const CapsuleException('This memory could not be found.');
      }

      // A link that lost its `#` fragment is not necessarily a dead end: if
      // the sender chose "openable with the code too", the key comes back with
      // the capsule and the recipient never learns anything went missing.
      _encryptionKey ??= capsule.codeUnlockKey;

      await SupabaseService.upsertReceivedCapsule(
        userId: userId,
        capsuleId: capsule.id,
        shareId: capsule.shareId,
        unlockTime: capsule.unlockTime,
        latitude: capsule.latitude,
        longitude: capsule.longitude,
        // Null when the link arrived without its fragment. The upsert
        // deliberately omits a null key rather than writing one, so a later
        // paste of the full link can fill it in without being overwritten.
        encryptionKey: _encryptionKey,
        fromName: widget.fromName,
        capsuleCreatedAt: capsule.createdAt,
      );

      if (!mounted) return;
      setState(() {
        _capsule = capsule;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
      AppSnackbar.showError(context, e);
    }
  }

  bool get _isReady {
    final c = _capsule;
    if (c == null) return false;
    return c.isUnlocked && !c.isPending;
  }

  /// Accepts the full link pasted by the user when the key did not survive the
  /// trip. Only a link for THIS memory is accepted — pasting someone else's
  /// would silently swap which memory they are about to open.
  Future<void> _submitFullLink() async {
    final parsed = ShareLinkParser.parseParts(_linkController.text);
    if (parsed is! ShareLinkModel || parsed.shareId != widget.shareId) {
      setState(() => _linkError = true);
      return;
    }

    setState(() {
      _encryptionKey = parsed.encryptionKey;
      _linkError = false;
    });

    // Persist the key so the Vault can open this memory later too.
    final userId = context.read<AuthProvider>().userId;
    final capsule = _capsule;
    if (userId != null && capsule != null) {
      try {
        await SupabaseService.upsertReceivedCapsule(
          userId: userId,
          capsuleId: capsule.id,
          shareId: capsule.shareId,
          unlockTime: capsule.unlockTime,
          latitude: capsule.latitude,
          longitude: capsule.longitude,
          encryptionKey: parsed.encryptionKey,
          fromName: widget.fromName ?? parsed.fromName,
          capsuleCreatedAt: capsule.createdAt,
        );
      } catch (e) {
        if (mounted) AppSnackbar.showError(context, e);
      }
    }
  }

  void _goBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      enterAppAfterRecipient(context);
    }
  }

  void _openVault() {
    // Hands over to the shared recipient exit, which lands on Home *with the
    // Vault open on top* — and, unlike a bare push, also releases the pending
    // share link and routes through onboarding when it has not been done yet.
    enterAppAfterRecipient(context, landOnVault: true);
  }

  void _openNow() {
    final key = _encryptionKey;
    if (key == null) return; // The button is not offered without a key.
    final nav = Navigator.of(context);
    final radarPage = SpringPageRoute(
      page: RadarScreen(
        shareId: widget.shareId,
        encryptionKey: key,
        fromName: widget.fromName,
      ),
    );
    if (nav.canPop()) {
      nav.pushReplacement(radarPage);
    } else {
      nav.pushAndRemoveUntil(radarPage, (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final from = NameFormat.display(widget.fromName);
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(canPop ? Icons.arrow_back : Icons.close),
          onPressed: _goBack,
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.containerMargin),
          child: _loading
              ? const _GiftSkeleton()
              : _failed
                  ? _GiftError(onClose: _goBack)
                  : Column(
                      children: [
                        const Spacer(flex: 2),
                        Icon(
                          Icons.hourglass_bottom_rounded,
                          size: 56,
                          color: AppColors.primary.withValues(alpha: 0.85),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        // One sentence, not a headline with a fragment stuck
                        // under it. "Someone left you a memory" + "from dani"
                        // read as a single broken line on the screen.
                        Text(
                          from == null
                              ? 'Someone left you a memory.'
                              : '$from left you a memory.',
                          textAlign: TextAlign.center,
                          style: AppTypography.headlineLg,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          !_hasKey
                              ? 'To open it, TimeDrop needs the whole link — the '
                                  'part after the # carries the key, and it did '
                                  'not come through.'
                              : _isReady
                                  ? 'It\'s ready to discover — find the place and open it.'
                                  : 'It\'s been saved to your Vault. When the time comes, open it there.',
                          textAlign: TextAlign.center,
                          style: AppTypography.bodyMd.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),

                        // ── Missing key: ask for the full link ──────────────
                        if (!_hasKey) ...[
                          const SizedBox(height: AppSpacing.lg),
                          TextField(
                            controller: _linkController,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: InputDecoration(
                              hintText: 'Paste the full link',
                              errorText: _linkError
                                  ? 'That link is for a different memory, or it '
                                      'is still missing the key.'
                                  : null,
                            ),
                            onSubmitted: (_) => _submitFullLink(),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          PrimaryButton(label: 'Unlock', onPressed: _submitFullLink),
                          const Spacer(flex: 3),
                          TextButton(
                            onPressed: _goBack,
                            child: Text(
                              'Later',
                              style: AppTypography.labelMd
                                  .copyWith(color: AppColors.onSurfaceVariant),
                            ),
                          ),
                        ] else ...[
                          if (!_isReady && _capsule != null) ...[
                            const SizedBox(height: AppSpacing.xl),
                            CountdownTimer(target: _capsule!.unlockTime),
                          ],
                          const Spacer(flex: 3),
                          if (_isReady) ...[
                            PrimaryButton(label: 'Open now', onPressed: _openNow),
                            const SizedBox(height: AppSpacing.sm),
                            TextButton(
                              onPressed: _goBack,
                              child: Text(
                                'Save for later',
                                style: AppTypography.labelMd.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ] else if (!canPop) ...[
                            // Fresh receive from a link: guide user to the Vault.
                            PrimaryButton(label: 'Open my vault', onPressed: _openVault),
                          ],
                          // When canPop=true (came from the Vault), no bottom
                          // button is needed — the AppBar back arrow suffices.
                        ],
                      ],
                    ),
        ),
      ),
    );
  }
}

class _GiftSkeleton extends StatelessWidget {
  const _GiftSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Spacer(flex: 2),
        SkeletonBox(width: 56, height: 56, borderRadius: 28),
        SizedBox(height: AppSpacing.lg),
        SkeletonBox(width: 260, height: 32, borderRadius: 8),
        SizedBox(height: AppSpacing.sm),
        SkeletonBox(width: 140, height: 20, borderRadius: 6),
        Spacer(flex: 3),
        SkeletonBox(width: double.infinity, height: 52, borderRadius: 16),
      ],
    );
  }
}

class _GiftError extends StatelessWidget {
  const _GiftError({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Could not open this drop.', style: AppTypography.headlineMd),
        const SizedBox(height: AppSpacing.lg),
        PrimaryButton(label: 'Close', onPressed: onClose),
      ],
    );
  }
}
