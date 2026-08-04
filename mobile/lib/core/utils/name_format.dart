/// Tidies the sender's name for display.
///
/// The name is free text typed into a box on the config screen, and it then
/// appears inside sentences the recipient reads at the most charged moment the
/// app has: "dani left you a memory." reads like a bug, and a name pasted with
/// a trailing newline or forty characters of enthusiasm breaks the layout it
/// lands in. This normalises all of that in one place, so every screen that
/// shows a sender's name shows the same one.
class NameFormat {
  NameFormat._();

  /// Beyond this a "name" is something else — a sentence, a URL, a paste
  /// accident — and no line of copy can accommodate it.
  static const int maxLength = 24;

  /// Returns the display form of [raw], or null when there is no usable name.
  ///
  /// Trims, collapses runs of whitespace, caps the length, and capitalises the
  /// first letter. Deliberately only the *first* letter: "de Souza" and
  /// "McKay" are names people write on purpose, and title-casing every word
  /// would quietly correct them into something else.
  static String? display(String? raw) {
    if (raw == null) return null;
    final collapsed = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (collapsed.isEmpty) return null;

    final clipped = collapsed.length > maxLength
        ? '${collapsed.substring(0, maxLength).trimRight()}…'
        : collapsed;

    return clipped[0].toUpperCase() + clipped.substring(1);
  }
}
