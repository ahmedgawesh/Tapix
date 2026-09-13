import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/core/bloc/theme_bloc.dart';
import 'package:tapix/core/services/theme_service.dart';
import 'package:tapix/core/widgets/theme_toggle_button.dart';

void main() {
  testWidgets('cashier theme button switches directly between light and dark', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'light'});
    final preferences = await SharedPreferences.getInstance();
    final service = ThemeService(preferences);
    final bloc = ThemeBloc(service);
    addTearDown(() async {
      await bloc.close();
      await service.dispose();
    });

    await tester.pumpWidget(
      BlocProvider.value(
        value: bloc,
        child: BlocBuilder<ThemeBloc, RealtimeState<ThemeMode>>(
          builder: (context, state) {
            final mode = state is RealtimeSuccess<ThemeMode>
                ? state.data
                : ThemeMode.system;
            return MaterialApp(
              theme: ThemeData.light(),
              darkTheme: ThemeData.dark(),
              themeMode: mode,
              home: Scaffold(
                appBar: AppBar(
                  actions: const [ThemeToggleButton(lightDarkOnly: true)],
                ),
              ),
            );
          },
        ),
      ),
    );

    expect(find.byIcon(LucideIcons.moon), findsOneWidget);
    await tester.tap(find.byType(ThemeToggleButton));
    await tester.pumpAndSettle();

    expect(preferences.getString('theme_mode'), 'dark');
    expect(find.byIcon(LucideIcons.sun), findsOneWidget);

    await tester.tap(find.byType(ThemeToggleButton));
    await tester.pumpAndSettle();

    expect(preferences.getString('theme_mode'), 'light');
    expect(find.byIcon(LucideIcons.moon), findsOneWidget);
  });
}
