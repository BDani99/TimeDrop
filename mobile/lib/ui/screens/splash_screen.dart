import 'package:flutter/material.dart';

/// Shown by [MainRouter] while it bootstraps auth + checks the clipboard.
/// Background colour exactly matches the native OS splash screen
/// (flutter_native_splash color #F1E8DF) so the transition is seamless.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  // Sampled from the top-left corner of assets/icon/splash.jpg.
  static const _bgColor = Color(0xFFF1E8DF);

  @override
  Widget build(BuildContext context) {
    return const Scaffold(backgroundColor: _bgColor);
  }
}
