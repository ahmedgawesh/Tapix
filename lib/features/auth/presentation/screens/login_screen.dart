import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/biometric_service.dart';
import '../../../../core/services/lan/lan_network_service.dart';
import '../../../settings/presentation/bloc/app_settings_bloc.dart';
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
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkBiometricAvailability();
  }

  Future<void> _checkBiometricAvailability() async {
    try {
      final settings = context.read<AppSettingsBloc>().state.settings;
      if (!settings.enableBiometricLogin) return;
      final available = await sl<BiometricService>().isBiometricAvailable();
      if (mounted) setState(() => _biometricAvailable = available);
    } catch (_) {}
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onLogin() {
    final lan = sl<LanNetworkService>().snapshot;
    if (lan.mode == LanMode.client &&
        lan.status != LanConnectionStatus.paired) {
      context.push('/device-connect');
      return;
    }
    if (_formKey.currentState?.validate() ?? false) {
      context.read<AuthBloc>().add(
        AuthLoginRequested(
          username: _usernameController.text.trim(),
          password: _passwordController.text,
          rememberMe: _rememberMe,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final lanSnapshot = sl<LanNetworkService>().snapshot;

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
                      const SizedBox(height: 24),
                      Card(
                        color: lanSnapshot.mode == LanMode.client
                            ? colorScheme.primaryContainer
                            : colorScheme.surfaceContainerHighest,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    lanSnapshot.mode == LanMode.client
                                        ? LucideIcons.wifi
                                        : LucideIcons.network,
                                    color: colorScheme.primary,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      lanSnapshot.mode == LanMode.client
                                          ? 'auth.master_paired'.tr(
                                              args: [
                                                lanSnapshot.masterHost ?? '—',
                                              ],
                                            )
                                          : 'auth.connect_master_hint'.tr(),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: () =>
                                    context.push('/device-connect'),
                                icon: const Icon(LucideIcons.link),
                                label: Text(
                                  lanSnapshot.mode == LanMode.client
                                      ? 'auth.change_master'.tr()
                                      : 'auth.connect_master'.tr(),
                                ),
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
                      if (lanSnapshot.mode != LanMode.client)
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
                              onPressed: () => context.go('/forgot-password'),
                              child: Text('auth.forgot_password'.tr()),
                            ),
                          ],
                        )
                      else
                        Text(
                          'auth.master_credentials_hint'.tr(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
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
                      if (_biometricAvailable &&
                          lanSnapshot.mode != LanMode.client) ...[
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: () {
                            context.read<AuthBloc>().add(
                              const AuthBiometricLoginRequested(),
                            );
                          },
                          icon: const Icon(LucideIcons.fingerprint),
                          label: Text('auth.biometric_login'.tr()),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ],
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
