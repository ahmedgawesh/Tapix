import 'package:flutter/material.dart';

/// Keeps report placeholders centered when space is available and makes them
/// vertically scrollable when compact screens cannot fit their full content.
class ReportScrollableCenter extends StatelessWidget {
  final Widget child;

  const ReportScrollableCenter({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final minHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : 0.0;
        return SingleChildScrollView(
          primary: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Center(child: child),
          ),
        );
      },
    );
  }
}
