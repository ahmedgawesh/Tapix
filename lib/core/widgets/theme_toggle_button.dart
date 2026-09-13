import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../bloc/theme_bloc.dart';
import '../bloc/realtime_bloc.dart';

class ThemeToggleButton extends StatelessWidget {
  final bool lightDarkOnly;

  const ThemeToggleButton({super.key, this.lightDarkOnly = false});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeBloc, RealtimeState<ThemeMode>>(
      builder: (context, state) {
        final currentMode = state is RealtimeSuccess<ThemeMode>
            ? state.data
            : ThemeMode.system;

        if (lightDarkOnly) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return IconButton(
            icon: Icon(isDark ? LucideIcons.sun : LucideIcons.moon),
            tooltip: isDark
                ? 'welcome.theme_light'.tr()
                : 'welcome.theme_dark'.tr(),
            onPressed: () {
              context.read<ThemeBloc>().add(
                ThemeChanged(isDark ? ThemeMode.light : ThemeMode.dark),
              );
            },
          );
        }

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
        return 'welcome.theme_light'.tr();
      case ThemeMode.dark:
        return 'welcome.theme_dark'.tr();
      case ThemeMode.system:
        return 'welcome.theme_system'.tr();
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
