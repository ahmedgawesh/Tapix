import 'package:flutter/material.dart';

import 'demo_config.dart';

/// A persistent "DEMO" watermark overlay shown on every screen in demo mode.
class DemoOverlay extends StatelessWidget {
  final Widget child;

  const DemoOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!DemoConfig.isDemo) return child;

    return Stack(
      children: [
        child,
        // Watermark
        Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: Transform.rotate(
                angle: -0.3,
                child: Text(
                  'DEMO',
                  style: TextStyle(
                    fontSize: 120,
                    fontWeight: FontWeight.w900,
                    color: Colors.grey.withValues(alpha: 0.07),
                    letterSpacing: 20,
                  ),
                ),
              ),
            ),
          ),
        ),
        // Top banner
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 2),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.orange.shade700,
                    Colors.deepOrange.shade600,
                  ],
                ),
              ),
              child: const Text(
                '🔒 DEMO MODE — No data is saved',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
