import 'package:flutter/material.dart';

/// A single-line text that auto-scrolls horizontally when its content is wider
/// than the available width.
///
/// When the rendered text fits inside [BoxConstraints.maxWidth] (provided by
/// a parent such as `Flexible` / `Expanded` / a bounded `SizedBox`), nothing
/// animates — the widget just behaves like a plain [Text]. As soon as the
/// content overflows the allotted width, it loops:
///   forward → pause → back → pause → forward …
///
/// This is the same primitive used by the categories screen for long category
/// names. It is intentionally tiny (no external `marquee` package): the
/// animation is driven by a private [ScrollController] inside a
/// [SingleChildScrollView] with [NeverScrollableScrollPhysics] so the user
/// cannot drag it manually — purely passive eye-candy.
///
/// Parent MUST provide a bounded `maxWidth` (e.g. by wrapping in `Flexible`
/// inside a Row). When `maxWidth` is unbounded the inner [LayoutBuilder]
/// would let the text take its intrinsic width and the marquee never kicks
/// in, which is the correct fallback for `MainAxisSize.min` parents.
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final int maxLines;

  const MarqueeText({
    super.key,
    required this.text,
    this.style,
    this.maxLines = 1,
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> {
  final ScrollController _controller = ScrollController();
  bool _isDisposed = false;
  double _lastMaxScrollExtent = 0;

  @override
  void dispose() {
    _isDisposed = true;
    _controller.dispose();
    super.dispose();
  }

  Future<void> _animateIfNeeded() async {
    if (_isDisposed) return;
    if (!_controller.hasClients) return;
    final max = _controller.position.maxScrollExtent;
    if (max <= 0) return;
    if (_lastMaxScrollExtent == max) return;
    _lastMaxScrollExtent = max;

    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (_isDisposed) return;
    if (!_controller.hasClients) return;

    while (!_isDisposed && _controller.hasClients) {
      final maxScroll = _controller.position.maxScrollExtent;
      if (maxScroll <= 0) return;
      final durationMs = (maxScroll * 25).clamp(900, 6000).toInt();
      await _controller.animateTo(
        maxScroll,
        duration: Duration(milliseconds: durationMs),
        curve: Curves.linear,
      );
      if (_isDisposed) return;
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (_isDisposed) return;
      await _controller.animateTo(
        0,
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOut,
      );
      if (_isDisposed) return;
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _animateIfNeeded();
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Text(
              widget.text,
              style: widget.style,
              maxLines: widget.maxLines,
              overflow: TextOverflow.visible,
              softWrap: false,
            ),
          ),
        );
      },
    );
  }
}
