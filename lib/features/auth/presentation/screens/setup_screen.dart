import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../domain/entities/user_entity.dart';
import '../bloc/auth_bloc.dart';
import '../widgets/auth_text_field.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _onCreateAccount() {
    if (_formKey.currentState?.validate() ?? false) {
      context.read<AuthBloc>().add(AuthFirstOwnerCreated(
            username: _usernameController.text.trim(),
            password: _passwordController.text,
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
    final logoSize = isDesktop ? 120.0 : (isTablet ? 100.0 : 80.0);
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
                        width: logoSize,
                        height: logoSize,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'auth.setup_title',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ).tr(),
                      const SizedBox(height: 8),
                      Text(
                        'auth.setup_subtitle',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ).tr(),
                      const SizedBox(height: 32),
                      Card(
                        color: colorScheme.surfaceContainerHighest,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(
                                LucideIcons.info,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'auth.setup_info',
                                  style: theme.textTheme.bodySmall,
                                ).tr(),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
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
                          if (value.trim().length < 3) {
                            return 'auth.username_min_length'.tr();
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
                        textInputAction: TextInputAction.next,
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
                          if (value.length < 6) {
                            return 'auth.password_min_length'.tr();
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      AuthTextField(
                        controller: _confirmPasswordController,
                        labelText: 'auth.confirm_password'.tr(),
                        hintText: 'auth.confirm_password_hint'.tr(),
                        prefixIcon: LucideIcons.keyRound,
                        obscureText: _obscureConfirmPassword,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _onCreateAccount(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirmPassword
                                ? LucideIcons.eye
                                : LucideIcons.eyeOff,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureConfirmPassword = !_obscureConfirmPassword;
                            });
                          },
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'auth.confirm_password_required'.tr();
                          }
                          if (value != _passwordController.text) {
                            return 'auth.passwords_dont_match'.tr();
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 32),
                      BlocBuilder<AuthBloc, RealtimeState<UserEntity?>>(
                        builder: (context, state) {
                          final isLoading = state is AuthLoading;
                          return FilledButton.icon(
                            onPressed: isLoading ? null : _onCreateAccount,
                            icon: isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(LucideIcons.check),
                            label: Text('auth.create_account'.tr()),
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
