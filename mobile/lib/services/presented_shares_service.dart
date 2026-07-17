import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Remembers which shareIds have already been shown via [GiftReceivedScreen]
/// so clipboard auto-open only fires once per capsule.
class PresentedSharesService {
  PresentedSharesService._();

  static const _fileName = 'presented_share_ids.json';
  static Set<String>? _cache;

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<Set<String>> _load() async {
    if (_cache != null) return _cache!;
    try {
      final file = await _file();
      if (!await file.exists()) {
        _cache = <String>{};
        return _cache!;
      }
      final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
      _cache = raw.map((e) => e as String).toSet();
    } catch (e) {
      debugPrint('PresentedSharesService: corrupt store, resetting: $e');
      _cache = <String>{};
    }
    return _cache!;
  }

  static Future<void> _persist() async {
    final file = await _file();
    await file.writeAsString(jsonEncode(_cache!.toList()));
  }

  static Future<bool> hasPresented(String shareId) async {
    final ids = await _load();
    return ids.contains(shareId);
  }

  static Future<void> markPresented(String shareId) async {
    final ids = await _load();
    if (ids.add(shareId)) await _persist();
  }
}
