import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

/// Extracts a dominant accent color from image bytes for adaptive memory cards.
class ColorPaletteExtractor {
  ColorPaletteExtractor._();

  static final _cache = <String, Color>{};

  static Future<Color?> extract({
    required String cacheKey,
    required Uint8List imageBytes,
    Color fallback = const Color(0xFFA33D25),
  }) async {
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    try {
      final codec = await ui.instantiateImageCodec(imageBytes, targetWidth: 64);
      final frame = await codec.getNextFrame();
      final palette = await PaletteGenerator.fromImage(
        frame.image,
        maximumColorCount: 8,
      );
      final color = palette.vibrantColor?.color ??
          palette.dominantColor?.color ??
          palette.mutedColor?.color ??
          fallback;
      _cache[cacheKey] = color;
      return color;
    } catch (_) {
      return fallback;
    }
  }

  static Color? cached(String cacheKey) => _cache[cacheKey];
}
