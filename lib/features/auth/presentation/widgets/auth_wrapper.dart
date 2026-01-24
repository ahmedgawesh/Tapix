import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../domain/entities/user_entity.dart';
import '../bloc/auth_bloc.dart';
import '../screens/login_screen.dart';
import '../screens/setup_screen.dart';

class AuthWrapper extends StatelessWidget {
  final Widget child;

  const AuthWrapper({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, RealtimeState<UserEntity?>>(
      builder: (context, state) {
        if (state is AuthInitial || state is AuthLoading) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (state is AuthNeedsSetup) {
          return const SetupScreen();
        }

        if (state is AuthUnauthenticated || state is AuthError) {
          return const LoginScreen();
        }

        if (state is AuthAuthenticated) {
          return child;
        }

        return const LoginScreen();
      },
    );
  }
}
