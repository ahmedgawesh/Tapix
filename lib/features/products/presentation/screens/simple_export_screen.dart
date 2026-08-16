import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/export_file_saver.dart';
import '../../../../core/services/logging_service.dart';
import '../../../auth/auth.dart';
import '../bloc/export_bloc.dart';
import '../bloc/export_event.dart';
import '../bloc/export_state.dart';
import '../widgets/export_format_selector.dart';
import '../widgets/export_preview_widget.dart';
import '../widgets/export_progress_widget.dart';

class SimpleExportScreen extends StatelessWidget {
  const SimpleExportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Check permissions - only Manager/Owner can export
    final authBloc = sl<AuthBloc>();
    final authState = authBloc.state;

    if (authState is! AuthAuthenticated) {
      return Scaffold(
        appBar: AppBar(title: Text('export_products.title'.tr())),
        body: Center(child: Text('common.unauthorized'.tr())),
      );
    }

    final user = authState.user;
    if (user.role != UserRole.owner && user.role != UserRole.manager) {
      return Scaffold(
        appBar: AppBar(title: Text('export_products.title'.tr())),
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
                onPressed: () => Navigator.of(context).maybePop(),
                child: Text('common.back'.tr()),
              ),
            ],
          ),
        ),
      );
    }

    return BlocProvider(
      create: (context) => sl<ExportBloc>()..add(const LoadExportPreview()),
      child: const _SimpleExportScreenContent(),
    );
  }
}

class _SimpleExportScreenContent extends StatelessWidget {
  const _SimpleExportScreenContent();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('export_products.title'.tr()),
        centerTitle: true,
      ),
      body: SafeArea(
        child: BlocConsumer<ExportBloc, RealtimeState<ExportUiData>>(
          listener: (context, state) async {
            if (state is RealtimeSuccess<ExportUiData> &&
                state.data.lastExport != null) {
              await _handleExportSuccess(context, state.data.lastExport!);
              if (context.mounted) {
                context.read<ExportBloc>().add(const ExportAcknowledged());
              }
              return;
            }

            if (state is RealtimeError<ExportUiData>) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('export_products.error'.tr()),
                  backgroundColor: colorScheme.error,
                ),
              );
            }
          },
          builder: (context, state) {
            return LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = constraints.maxWidth < 600;

                final data = state is RealtimeSuccess<ExportUiData>
                    ? state.data
                    : state is RealtimeLoading<ExportUiData>
                    ? state.previousData
                    : state is RealtimeError<ExportUiData>
                    ? state.previousData
                    : null;

                final products = data?.products ?? const [];
                final isExporting =
                    data?.operationStatus == ExportOperationStatus.inProgress;
                final selectedIds = data?.selectedProductIds ?? <int>{};

                return SingleChildScrollView(
                  padding: EdgeInsets.all(isMobile ? 16 : 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildFormatSelector(context),
                      const SizedBox(height: 24),
                      _buildFilterSection(context, isMobile),
                      const SizedBox(height: 24),
                      if (products.isNotEmpty) ...[
                        _buildPreviewSection(context, products, selectedIds),
                        const SizedBox(height: 24),
                      ],
                      if (isExporting) ...[
                        ExportProgressWidget(progress: data?.progress),
                        const SizedBox(height: 24),
                      ],
                      _buildExportActions(context, data, isExporting),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildFormatSelector(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'export_products.format_selection'.tr(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            const ExportFormatSelector(),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterSection(BuildContext context, bool isMobile) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'export_products.filters'.tr(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Text(
              'export_products.filters_description'.tr(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewSection(
    BuildContext context,
    List<dynamic> products,
    Set<int> selectedIds,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'export_products.preview'.tr(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            ExportPreviewWidget(
              products: products.cast(),
              selectedProductIds: selectedIds,
              onToggleSelectAll: () => context.read<ExportBloc>().add(
                const ToggleSelectAllProducts(),
              ),
              onToggleProduct: (id) =>
                  context.read<ExportBloc>().add(ToggleProductSelection(id)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExportActions(
    BuildContext context,
    ExportUiData? data,
    bool isExporting,
  ) {
    final currentFormat = data?.format ?? ExportFormat.csv;
    final selectedCount = (data?.selectedProductIds ?? <int>{}).length;

    final isMobile = MediaQuery.of(context).size.width < 600;

    final saveButton = FilledButton.icon(
      onPressed: isExporting
          ? null
          : () => _handleExport(context, currentFormat, ExportAction.save),
      icon: isExporting
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(LucideIcons.save),
      label: Text(
        isExporting
            ? 'export_products.exporting'.tr()
            : '${'common.save'.tr()}${selectedCount > 0 ? ' ($selectedCount)' : ''}',
      ),
    );

    final shareSupported =
        kIsWeb || defaultTargetPlatform != TargetPlatform.linux;
    final shareButton = OutlinedButton.icon(
      onPressed: (!shareSupported || isExporting)
          ? null
          : () => _handleExport(context, currentFormat, ExportAction.share),
      icon: const Icon(LucideIcons.share2),
      label: Text('common.share'.tr()),
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [saveButton, const SizedBox(height: 12), shareButton],
      );
    }

    return Row(
      children: [
        Expanded(child: saveButton),
        const SizedBox(width: 12),
        Expanded(child: shareButton),
      ],
    );
  }

  void _handleExport(
    BuildContext context,
    ExportFormat format,
    ExportAction action,
  ) {
    LoggingService.methodEntry(
      '_handleExport',
      params: {'format': format.toString(), 'action': action.toString()},
      tag: 'SimpleExportScreen',
    );

    final bloc = context.read<ExportBloc>();

    if (format == ExportFormat.csv) {
      LoggingService.blocEvent(
        'ExportBloc',
        'ExportToCSV',
        tag: 'SimpleExportScreen',
      );
      bloc.add(ExportToCSV(action: action));
    } else {
      LoggingService.blocEvent(
        'ExportBloc',
        'ExportToExcel',
        tag: 'SimpleExportScreen',
      );
      bloc.add(ExportToExcel(action: action));
    }
  }

  Future<void> _handleExportSuccess(
    BuildContext context,
    ExportPayload payload,
  ) async {
    final colorScheme = Theme.of(context).colorScheme;

    LoggingService.methodEntry(
      '_handleExportSuccess',
      params: {
        'filename': payload.filename,
        'format': payload.format.toString(),
        'size': '${payload.bytes.length} bytes',
      },
      tag: 'SimpleExportScreen',
    );

    try {
      final mimeType = payload.format == ExportFormat.csv
          ? 'text/csv'
          : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

      if (payload.action == ExportAction.save) {
        final saver = createExportFileSaver();
        final saved = await saver.saveBytes(
          bytes: payload.bytes,
          filename: payload.filename,
          mimeType: mimeType,
        );

        if (!saved) {
          throw Exception('Save cancelled');
        }
      } else {
        final shareSupported =
            kIsWeb || defaultTargetPlatform != TargetPlatform.linux;
        if (!shareSupported) {
          final saver = createExportFileSaver();
          await saver.saveBytes(
            bytes: payload.bytes,
            filename: payload.filename,
            mimeType: mimeType,
          );
        } else {
          LoggingService.serviceOperation(
            'SharePlus',
            'share',
            tag: 'SimpleExportScreen',
          );

          final xFile = XFile.fromData(
            payload.bytes,
            name: payload.filename,
            mimeType: mimeType,
          );

          await SharePlus.instance.share(
            ShareParams(
              files: [xFile],
              subject: 'export_products.share_message'.tr(),
            ),
          );
        }
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('export_products.success'.tr()),
          backgroundColor: colorScheme.primary,
        ),
      );
    } catch (e, st) {
      LoggingService.error(
        'Failed to share file',
        error: e,
        stackTrace: st,
        params: {
          'filename': payload.filename,
          'format': payload.format.toString(),
        },
        tag: 'SimpleExportScreen',
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('export_products.save_error'.tr()),
          backgroundColor: colorScheme.error,
        ),
      );
    } finally {
      LoggingService.methodExit(
        '_handleExportSuccess',
        tag: 'SimpleExportScreen',
      );
    }
  }
}
