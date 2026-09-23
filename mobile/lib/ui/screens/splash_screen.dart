import 'package:flutter/material.dart';

/// Shown by [MainRouter] while it bootstraps auth + checks the clipboard.
/// Background colour exactly matches the native OS splash screen
/// (flutter_native_splash color #F1E5D8) so the transition is seamless.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  // Median edge colour sampled from assets/icon/splash.jpg.
  static const backgroundColor = Color(0xFFF1E5D8);

  @override
  Widget build(BuildContext context) {
    return const Scaffold(backgroundColor: backgroundColor);
  }
}
