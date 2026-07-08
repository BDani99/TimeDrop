import 'package:flutter/material.dart';

/// Corner radii from `design/DESIGN.md`. Cards use 24px+, small controls
/// use the pill (`full`) shape.
class AppRadii {
  AppRadii._();

  static const double sm = 8; // 0.5rem
  static const double base = 16; // 1rem
  static const double md = 24; // 1.5rem
  static const double lg = 32; // 2rem
  static const double xl = 48; // 3rem
  static const double full = 9999;

  static BorderRadius get smRadius => BorderRadius.circular(sm);
  static BorderRadius get baseRadius => BorderRadius.circular(base);
  static BorderRadius get mdRadius => BorderRadius.circular(md);
  static BorderRadius get lgRadius => BorderRadius.circular(lg);
  static const StadiumBorder pill = StadiumBorder();
}
