import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tapix/features/auth/auth.dart';

class MockAuthBloc extends Mock implements AuthBloc {
  final AuthState _state;
  
  MockAuthBloc(this._state);
  
  @override
  AuthState get state => _state;
  
  @override
  Stream<AuthState> get stream => Stream.value(_state);
  
  @override
  Future<void> close() async {}
}

void main() {
  testWidgets('Setup screen shows when AuthNeedsSetup state', (WidgetTester tester) async {
    final mockBloc = MockAuthBloc(const AuthNeedsSetup());
    
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<AuthBloc>.value(
          value: mockBloc,
          child: const AuthWrapper(child: Scaffold(body: Text('Home'))),
        ),
      ),
    );

    await tester.pump();

    expect(find.byType(SetupScreen), findsOneWidget);
  });

  testWidgets('Login screen shows when AuthUnauthenticated state', (WidgetTester tester) async {
    final mockBloc = MockAuthBloc(const AuthUnauthenticated());
    
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<AuthBloc>.value(
          value: mockBloc,
          child: const AuthWrapper(child: Scaffold(body: Text('Home'))),
        ),
      ),
    );

    await tester.pump();

    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('Home shows when AuthAuthenticated state', (WidgetTester tester) async {
    final user = UserEntity(
      id: 1,
      username: 'test',
      role: UserRole.owner,
      isActive: true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final mockBloc = MockAuthBloc(AuthAuthenticated(user: user));
    
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<AuthBloc>.value(
          value: mockBloc,
          child: const AuthWrapper(child: Scaffold(body: Text('Home Content'))),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('Home Content'), findsOneWidget);
  });
}
