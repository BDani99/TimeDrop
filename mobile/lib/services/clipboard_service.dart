import 'package:flutter/services.dart';

import '../core/utils/share_link_parser.dart';

/// Reads the OS clipboard and checks it for a TimeDrop share link — used by
/// `MainRouter` on splash and by the app-resume hook (Sprint 2).
class ClipboardService {
  ClipboardService._();

  static Future<ShareLinkModel?> checkClipboardForShareLink() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (text == null || text.isEmpty) return null;
      return ShareLinkParser.tryParse(text);
    } catch (_) {
      // Clipboard access can fail (platform restrictions); treat as "no link".
      return null;
    }
  }

  static Future<void> copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }
}
