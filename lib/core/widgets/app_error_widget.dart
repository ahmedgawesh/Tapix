import 'package:flutter/widgets.dart';

/// A minimal fallback used while Flutter is already handling a build failure.
///
/// It avoids every inherited dependency and every controller so it can also be
/// built while an overlay or route is being removed.
class AppErrorWidget extends StatelessWidget {
  final FlutterErrorDetails details;

  const AppErrorWidget({super.key, required this.details});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF7F7FA),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: RichText(
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.center,
            textScaler: TextScaler.noScaling,
            text: const TextSpan(
              style: TextStyle(
                inherit: false,
                color: Color(0xFF49454F),
                fontSize: 14,
              ),
              children: [
                TextSpan(
                  text: 'Something went wrong',
                  style: TextStyle(
                    inherit: false,
                    color: Color(0xFF1D1B20),
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(text: '\n\nClose this screen and try again.'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
