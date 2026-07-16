import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The sender's note shown over the video with a gentle character-by-character
/// reveal. Stays fully readable while [visible] is true and only fades out once
/// the parent flips [visible] to false — never mid-read.
class HandwrittenNoteOverlay extends StatefulWidget {
  const HandwrittenNoteOverlay({
    super.key,
    required this.note,
    required this.visible,
  });

  final String note;
  final bool visible;

  @override
  State<HandwrittenNoteOverlay> createState() => _HandwrittenNoteOverlayState();
}

class _HandwrittenNoteOverlayState extends State<HandwrittenNoteOverlay> {
  int _visibleChars = 0;
  bool _typing = false;

  @override
  void initState() {
    super.initState();
    if (widget.visible) _startTyping();
  }

  @override
  void didUpdateWidget(covariant HandwrittenNoteOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      _visibleChars = 0;
      _startTyping();
    }
  }

  Future<void> _startTyping() async {
    if (_typing || widget.note.isEmpty) return;
    _typing = true;
    await Future<void>.delayed(const Duration(milliseconds: 220));
    while (mounted && widget.visible && _visibleChars < widget.note.length) {
      await Future<void>.delayed(const Duration(milliseconds: 42));
      if (!mounted) return;
      setState(() => _visibleChars++);
    }
    _typing = false;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.note.isEmpty) return const SizedBox.shrink();

    final shown = widget.note.substring(0, _visibleChars.clamp(0, widget.note.length));

    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: widget.visible ? 1 : 0,
        duration: Duration(milliseconds: widget.visible ? 400 : 900),
        curve: Curves.easeInOut,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(28, 60, 28, 56),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x00000000),
                  Color(0x99000000),
                ],
              ),
            ),
            child: Text(
              shown,
              textAlign: TextAlign.center,
              style: GoogleFonts.playfairDisplay(
                fontSize: 22,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w500,
                color: Colors.white,
                height: 1.5,
                shadows: const [
                  Shadow(color: Colors.black87, blurRadius: 18),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
