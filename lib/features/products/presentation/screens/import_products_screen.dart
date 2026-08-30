import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../core/di/injection_container.dart';
import '../../../auth/auth.dart';
import '../bloc/import_products_bloc.dart';
import '../bloc/import_products_event.dart';
import '../bloc/import_products_state.dart';
import '../widgets/column_mapping_widget.dart';
import '../widgets/import_preview_widget.dart';
import '../widgets/import_progress_widget.dart';
import '../widgets/import_result_widget.dart';

class ImportProductsScreen extends StatelessWidget {
  const ImportProductsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Check permissions - only Manager/Owner can import
    final authBloc = sl<AuthBloc>();
    final authState = authBloc.state;

    if (authState is! AuthAuthenticated) {
      return Scaffold(
        appBar: AppBar(title: Text('import_products.title'.tr())),
        body: Center(child: Text('common.unauthorized'.tr())),
      );
    }

    final user = authState.user;
    if (user.role != UserRole.owner && user.role != UserRole.manager) {
      return Scaffold(
        appBar: AppBar(title: Text('import_products.title'.tr())),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                LucideIcons.lock,
                size: 64,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'import_products.permission_denied'.tr(),
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'import_products.manager_owner_only'.tr(),
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => context.pop(),
                child: Text('common.back'.tr()),
              ),
            ],
          ),
        ),
      );
    }

    return BlocProvider(
      create: (context) => sl<ImportProductsBloc>(),
      child: const _ImportProductsView(),
    );
  }
}

class _ImportProductsView extends StatelessWidget {
  const _ImportProductsView();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('import_products.title'.tr()),
        actions: [
          BlocBuilder<ImportProductsBloc, ImportProductsState>(
            builder: (context, state) {
              if (state is! ImportProductsInitial &&
                  state is! ImportCompleted) {
                return IconButton(
                  icon: const Icon(LucideIcons.x),
                  onPressed: () {
                    context.read<ImportProductsBloc>().add(const ImportReset());
                  },
                  tooltip: 'import_products.reset'.tr(),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: BlocConsumer<ImportProductsBloc, ImportProductsState>(
        listener: (context, state) {
          if (state is ImportFailed) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.errorMessage),
                backgroundColor: colorScheme.error,
                duration: const Duration(seconds: 5),
              ),
            );
          }
        },
        builder: (context, state) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth > 1024;
              final isTablet =
                  constraints.maxWidth > 600 && constraints.maxWidth <= 1024;

              return SafeArea(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(isDesktop ? 32 : 16),
                  child: _buildContent(context, state, isDesktop, isTablet),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    ImportProductsState state,
    bool isDesktop,
    bool isTablet,
  ) {
    if (state is ImportProductsInitial) {
      return _buildFileSelection(context, isDesktop);
    } else if (state is ImportFileLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(48),
          child: CircularProgressIndicator(),
        ),
      );
    } else if (state is ImportFileParsed || state is ImportColumnMappingReady) {
      return ColumnMappingWidget(
        state: state,
        isDesktop: isDesktop,
        isTablet: isTablet,
      );
    } else if (state is ImportValidating) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text('import_products.validating_data'.tr()),
            ],
          ),
        ),
      );
    } else if (state is ImportValidated) {
      return ImportPreviewWidget(
        state: state,
        isDesktop: isDesktop,
        isTablet: isTablet,
      );
    } else if (state is ImportInProgress) {
      return ImportProgressWidget(state: state, isDesktop: isDesktop);
    } else if (state is ImportCompleted) {
      return ImportResultWidget(result: state.result, isDesktop: isDesktop);
    } else if (state is ImportFailed) {
      return _buildErrorView(context, state);
    }

    return const SizedBox.shrink();
  }

  Widget _buildFileSelection(BuildContext context, bool isDesktop) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isDesktop ? 600 : double.infinity,
        ),
        child: Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.fileSpreadsheet,
                  size: 64,
                  color: colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  'import_products.select_file'.tr(),
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'import_products.supported_formats'.tr(),
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: () => _pickFile(context),
                  icon: const Icon(LucideIcons.upload),
                  label: Text('import_products.choose_file'.tr()),
                ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: () {
                    // TODO: Download sample template
                  },
                  icon: const Icon(LucideIcons.download),
                  label: Text('import_products.download_template'.tr()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorView(BuildContext context, ImportFailed state) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.alertCircle, size: 64, color: colorScheme.error),
              const SizedBox(height: 24),
              Text(
                'import_products.error_title'.tr(),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Text(
                state.errorMessage,
                textAlign: TextAlign.center,
                style: TextStyle(color: colorScheme.error),
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () {
                  context.read<ImportProductsBloc>().add(const ImportReset());
                },
                child: Text('import_products.try_again'.tr()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickFile(BuildContext context) async {
    try {
      try {
        await FilePicker.clearTemporaryFiles();
      } catch (e) {
        debugPrint('[ImportProductsScreen] clearTemporaryFiles failed: $e');
      }

      debugPrint('[ImportProductsScreen] Opening file picker');

      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx', 'xls'],
      );

      debugPrint(
        '[ImportProductsScreen] File picker result: ${file == null ? 'null' : file.name}',
      );

      if (file != null) {
        debugPrint(
          '[ImportProductsScreen] Selected: name=${file.name}, uri=${file.uri}',
        );

        final bytes = await file.readAsBytes();
        if (!context.mounted) return;
        context.read<ImportProductsBloc>().add(
          ImportFileSelected(fileBytes: bytes, fileName: file.name),
        );
      } else {
        if (!context.mounted) return;
        debugPrint(
          '[ImportProductsScreen] No file selected (cancelled or empty result)',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('import_products.file_pick_error'.tr()),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      debugPrint('[ImportProductsScreen] File picker error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('import_products.file_pick_error'.tr()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }
}
