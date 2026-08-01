import '../constants/app_constants.dart';
import '../errors/app_exception.dart';

/// A parsed TimeDrop share link: `{baseUrl}/c/{shareId}?from=<name>#{key}`.
/// The `from` query param is optional, non-sensitive personalization for
/// the web landing page (see plan assumption on the zero-backend web page);
/// it is never used for anything security-relevant.
class ShareLinkModel {
  const ShareLinkModel({required this.shareId, required this.encryptionKey, this.fromName});

  final String shareId;
  final String encryptionKey;
  final String? fromName;

  String toUrl() {
    final buffer = StringBuffer('${AppConstants.shareBaseUrl}/c/$shareId');
    if (fromName != null && fromName!.isNotEmpty) {
      buffer.write('?from=${Uri.encodeQueryComponent(fromName!)}');
    }
    buffer.write('#$encryptionKey');
    return buffer.toString();
  }
}

/// A TimeDrop link that names a real capsule but arrived WITHOUT its
/// decryption key.
///
/// This is not a hypothetical. The key lives in the URL fragment so it never
/// reaches the server, and Android does not reliably deliver the fragment with
/// an App Link intent. Rather than let such a link vanish silently, the parser
/// reports it and the UI asks for the full link.
class IncompleteShareLink {
  const IncompleteShareLink({required this.shareId, this.fromName});

  final String shareId;
  final String? fromName;
}

/// Builds and parses TimeDrop share links. Parsing must work on a plain
/// clipboard string (not a browser `window.location`), so we go through
/// `Uri.parse` and read `.fragment` directly — this works fine for a
/// well-formed absolute URI string.
class ShareLinkParser {
  ShareLinkParser._();

  static final RegExp _pathPattern = RegExp(r'^/c/([A-Za-z0-9]{6})$');

  /// Returns null if [text] doesn't look like a TimeDrop share link — callers
  /// treat that as "nothing to do", not an error.
  static ShareLinkModel? tryParse(String text) {
    final complete = _parseParts(text);
    return complete is ShareLinkModel ? complete : null;
  }

  /// Like [tryParse], but distinguishes the three outcomes:
  ///   * [ShareLinkModel]      — a complete, openable link
  ///   * [IncompleteShareLink] — our link, but the key is missing
  ///   * `null`                — not a TimeDrop link at all
  ///
  /// Deep-link entry points should use this, so a key-less link becomes a
  /// "paste the full link" prompt instead of being dropped on the floor.
  static Object? parseParts(String text) => _parseParts(text);

  static Object? _parseParts(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    Uri uri;
    try {
      uri = Uri.parse(trimmed);
    } catch (_) {
      return null;
    }

    final expectedHost = Uri.parse(AppConstants.shareBaseUrl).host;
    if (uri.host != expectedHost) return null;

    final match = _pathPattern.firstMatch(uri.path);
    if (match == null) return null;

    final shareId = match.group(1)!;
    final fromName = uri.queryParameters['from'];
    final key = uri.fragment;

    if (key.isEmpty) {
      return IncompleteShareLink(shareId: shareId, fromName: fromName);
    }
    return ShareLinkModel(shareId: shareId, encryptionKey: key, fromName: fromName);
  }

  /// Strict variant for callers that expect a valid link and want a
  /// surfaced error otherwise (e.g. manual "paste link" entry).
  static ShareLinkModel parse(String text) {
    final parsed = tryParse(text);
    if (parsed == null) {
      throw const CapsuleException('That doesn\'t look like a valid TimeDrop link.');
    }
    return parsed;
  }
}
