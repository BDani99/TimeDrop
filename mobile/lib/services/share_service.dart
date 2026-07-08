import 'package:share_plus/share_plus.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/share_link_parser.dart';

/// Builds the final share URL and hands it to the native OS share sheet.
class ShareService {
  ShareService._();

  static String buildShareUrl({
    required String shareId,
    required String encryptionKey,
    String? fromName,
  }) {
    return ShareLinkModel(
      shareId: shareId,
      encryptionKey: encryptionKey,
      fromName: fromName,
    ).toUrl();
  }

  static Future<void> shareCapsuleLink(String url) async {
    await Share.share('I left you a memory on ${AppConstants.appName}: $url');
  }
}
