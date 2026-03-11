import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../domain/entities/user_entity.dart';
import '../bloc/auth_bloc.dart';
import '../widgets/auth_text_field.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _usernameFormKey = GlobalKey<FormState>();
  final _resetFormKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _answerController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // Multi-step flow
  _ForgotPasswordStep _currentStep = _ForgotPasswordStep.enterUsername;
  String? _securityQuestion;
  String? _username;

  @override
  void dispose() {
    _usernameController.dispose();
    _answerController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _onFindAccount() {
    if (_usernameFormKey.currentState?.validate() ?? false) {
      _username = _usernameController.text.trim();
      context.read<AuthBloc>().add(
            AuthSecurityQuestionRequested(username: _username!),
          );
    }
  }

  void _onResetPassword() {
    if (_resetFormKey.currentState?.validate() ?? false) {
      context.read<AuthBloc>().add(
            AuthPasswordResetRequested(
              username: _username!,
              securityAnswer: _answerController.text,
              newPassword: _newPasswordController.text,
            ),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;

    final isDesktop = screenWidth >= 1024;
    final isTablet = screenWidth >= 600 && screenWidth < 1024;
    final maxWidth = isDesktop ? 450.0 : (isTablet ? 420.0 : 400.0);
    final padding = isDesktop ? 32.0 : (isTablet ? 28.0 : 24.0);

    return Scaffold(
      body: BlocListener<AuthBloc, RealtimeState<UserEntity?>>(
        listener: (context, state) {
          if (state is AuthSecurityQuestionLoaded) {
            setState(() {
              _securityQuestion = state.question;
              _currentStep = _ForgotPasswordStep.answerQuestion;
            });
          } else if (state is AuthSecurityQuestionNotSet) {
            setState(() {
              _currentStep = _ForgotPasswordStep.noQuestionSet;
            });
          } else if (state is AuthPasswordResetSuccess) {
            setState(() {
              _currentStep = _ForgotPasswordStep.success;
            });
          } else if (state is AuthPasswordResetFailed) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('auth.recovery.incorrect_answer'.tr()),
                backgroundColor: colorScheme.error,
              ),
            );
          } else if (state is AuthError) {
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
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Icon(
                      LucideIcons.keyRound,
                      size: 56,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'auth.recovery.title'.tr(),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _getSubtitle(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),

                    // Step content
                    _buildStepContent(context),

                    const SizedBox(height: 16),

                    // Back to login
                    if (_currentStep != _ForgotPasswordStep.success)
                      TextButton.icon(
                        onPressed: () => context.go('/login'),
                        icon: const Icon(LucideIcons.arrowLeft, size: 16),
                        label: Text('auth.recovery.back_to_login'.tr()),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _getSubtitle() {
    switch (_currentStep) {
      case _ForgotPasswordStep.enterUsername:
        return 'auth.recovery.enter_username_hint'.tr();
      case _ForgotPasswordStep.answerQuestion:
        return 'auth.recovery.answer_question_hint'.tr();
      case _ForgotPasswordStep.noQuestionSet:
        return 'auth.recovery.no_question_hint'.tr();
      case _ForgotPasswordStep.success:
        return 'auth.recovery.success_hint'.tr();
    }
  }

  Widget _buildStepContent(BuildContext context) {
    switch (_currentStep) {
      case _ForgotPasswordStep.enterUsername:
        return _buildUsernameStep(context);
      case _ForgotPasswordStep.answerQuestion:
        return _buildAnswerStep(context);
      case _ForgotPasswordStep.noQuestionSet:
        return _buildNoQuestionStep(context);
      case _ForgotPasswordStep.success:
        return _buildSuccessStep(context);
    }
  }

  Widget _buildUsernameStep(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Form(
      key: _usernameFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthTextField(
            controller: _usernameController,
            labelText: 'auth.username'.tr(),
            hintText: 'auth.username_hint'.tr(),
            prefixIcon: LucideIcons.user,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _onFindAccount(),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'auth.username_required'.tr();
              }
              return null;
            },
          ),
          const SizedBox(height: 24),
          BlocBuilder<AuthBloc, RealtimeState<UserEntity?>>(
            builder: (context, state) {
              final isLoading = state is AuthLoading;
              return FilledButton.icon(
                onPressed: isLoading ? null : _onFindAccount,
                icon: isLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.onPrimary,
                        ),
                      )
                    : const Icon(LucideIcons.search),
                label: Text('auth.recovery.find_account'.tr()),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAnswerStep(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Form(
      key: _resetFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Security question card
          Card(
            color: colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    LucideIcons.helpCircle,
                    color: colorScheme.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'auth.recovery.security_question'.tr(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _securityQuestion ?? '',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          AuthTextField(
            controller: _answerController,
            labelText: 'auth.recovery.your_answer'.tr(),
            hintText: 'auth.recovery.answer_hint'.tr(),
            prefixIcon: LucideIcons.messageCircle,
            textInputAction: TextInputAction.next,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'auth.recovery.answer_required'.tr();
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          AuthTextField(
            controller: _newPasswordController,
            labelText: 'auth.recovery.new_password'.tr(),
            hintText: 'auth.password_hint'.tr(),
            prefixIcon: LucideIcons.lock,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.next,
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? LucideIcons.eye : LucideIcons.eyeOff,
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
            onFieldSubmitted: (_) => _onResetPassword(),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirmPassword ? LucideIcons.eye : LucideIcons.eyeOff,
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
              if (value != _newPasswordController.text) {
                return 'auth.passwords_dont_match'.tr();
              }
              return null;
            },
          ),
          const SizedBox(height: 24),
          BlocBuilder<AuthBloc, RealtimeState<UserEntity?>>(
            builder: (context, state) {
              final isLoading = state is AuthLoading;
              return FilledButton.icon(
                onPressed: isLoading ? null : _onResetPassword,
                icon: isLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.onPrimary,
                        ),
                      )
                    : const Icon(LucideIcons.refreshCw),
                label: Text('auth.recovery.reset_password'.tr()),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNoQuestionStep(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  LucideIcons.alertTriangle,
                  color: colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'auth.recovery.no_question_message'.tr(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'auth.recovery.admin_reset_title'.tr(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'auth.recovery.admin_reset_message'.tr(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () {
            setState(() {
              _currentStep = _ForgotPasswordStep.enterUsername;
              _usernameController.clear();
            });
          },
          icon: const Icon(LucideIcons.arrowLeft, size: 16),
          label: Text('auth.recovery.try_another_account'.tr()),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessStep(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(
                  LucideIcons.checkCircle2,
                  size: 48,
                  color: colorScheme.onPrimaryContainer,
                ),
                const SizedBox(height: 16),
                Text(
                  'auth.recovery.success_title'.tr(),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onPrimaryContainer,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'auth.recovery.success_message'.tr(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () => context.go('/login'),
          icon: const Icon(LucideIcons.logIn),
          label: Text('auth.recovery.go_to_login'.tr()),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ],
    );
  }
}

enum _ForgotPasswordStep {
  enterUsername,
  answerQuestion,
  noQuestionSet,
  success,
}
