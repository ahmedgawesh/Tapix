import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../bloc/theme_bloc.dart';
import '../bloc/realtime_bloc.dart';

class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeBloc, RealtimeState<ThemeMode>>(
      builder: (context, state) {
        final currentMode = state is RealtimeSuccess<ThemeMode>
            ? state.data
            : ThemeMode.system;

        IconData icon;
        switch (currentMode) {
          case ThemeMode.light:
            icon = LucideIcons.sun;
            break;
          case ThemeMode.dark:
            icon = LucideIcons.moon;
            break;
          case ThemeMode.system:
            icon = LucideIcons.monitor;
            break;
        }

        return IconButton(
          icon: Icon(icon),
          tooltip: _getTooltip(currentMode),
          onPressed: () {
            final nextMode = _getNextMode(currentMode);
            context.read<ThemeBloc>().add(ThemeChanged(nextMode));
          },
        );
      },
    );
  }

  String _getTooltip(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light Mode';
      case ThemeMode.dark:
        return 'Dark Mode';
      case ThemeMode.system:
        return 'System Mode';
    }
  }

  ThemeMode _getNextMode(ThemeMode current) {
    switch (current) {
      case ThemeMode.light:
        return ThemeMode.dark;
      case ThemeMode.dark:
        return ThemeMode.system;
      case ThemeMode.system:
        return ThemeMode.light;
    }
  }
}
