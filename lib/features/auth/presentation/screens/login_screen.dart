import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../domain/entities/user_entity.dart';
import '../bloc/auth_bloc.dart';
import '../widgets/auth_text_field.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _rememberMe = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onLogin() {
    if (_formKey.currentState?.validate() ?? false) {
      context.read<AuthBloc>().add(AuthLoginRequested(
            username: _usernameController.text.trim(),
            password: _passwordController.text,
            rememberMe: _rememberMe,
          ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    
    // Responsive breakpoints
    final isDesktop = screenWidth >= 1024;
    final isTablet = screenWidth >= 600 && screenWidth < 1024;
    
    // Responsive sizing
    final logoSize = isDesktop ? 80.0 : (isTablet ? 72.0 : 64.0);
    final maxWidth = isDesktop ? 450.0 : (isTablet ? 420.0 : 400.0);
    final padding = isDesktop ? 32.0 : (isTablet ? 28.0 : 24.0);

    return Scaffold(
      body: BlocListener<AuthBloc, RealtimeState<UserEntity?>>( 
        listener: (context, state) {
          if (state is AuthError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: colorScheme.error,
              ),
            );
          }
        },
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(padding),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Logo instead of icon
                      Image.asset(
                        'assets/logos/logo.png',
                        width: logoSize * 2,
                        height: logoSize,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'auth.login_title',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ).tr(),
                      const SizedBox(height: 8),
                      Text(
                        'auth.login_subtitle',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ).tr(),
                      const SizedBox(height: 32),
                      AuthTextField(
                        controller: _usernameController,
                        labelText: 'auth.username'.tr(),
                        hintText: 'auth.username_hint'.tr(),
                        prefixIcon: LucideIcons.user,
                        textInputAction: TextInputAction.next,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'auth.username_required'.tr();
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      AuthTextField(
                        controller: _passwordController,
                        labelText: 'auth.password'.tr(),
                        hintText: 'auth.password_hint'.tr(),
                        prefixIcon: LucideIcons.lock,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _onLogin(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? LucideIcons.eye
                                : LucideIcons.eyeOff,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'auth.password_required'.tr();
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Checkbox(
                                value: _rememberMe,
                                onChanged: (value) {
                                  setState(() {
                                    _rememberMe = value ?? false;
                                  });
                                },
                              ),
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _rememberMe = !_rememberMe;
                                  });
                                },
                                child: Text('auth.remember_me'.tr()),
                              ),
                            ],
                          ),
                          TextButton(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('auth.forgot_password_coming_soon'.tr()),
                                ),
                              );
                            },
                            child: Text('auth.forgot_password'.tr()),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      BlocBuilder<AuthBloc, RealtimeState<UserEntity?>>(
                        builder: (context, state) {
                          final isLoading = state is AuthLoading;
                          return FilledButton.icon(
                            onPressed: isLoading ? null : _onLogin,
                            icon: isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(LucideIcons.logIn),
                            label: Text('auth.login'.tr()),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
