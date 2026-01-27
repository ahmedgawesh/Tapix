import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../products/domain/entities/product_entity.dart';
import '../../domain/models/barcode_design_state.dart';
import '../bloc/barcode_design_bloc.dart';
import '../bloc/barcode_design_event.dart';
import '../widgets/barcode_preview_widget.dart';
import '../widgets/template_selector_widget.dart';
import '../widgets/design_settings_widget.dart';
import '../widgets/product_selection_widget.dart';

class BarcodeDesignScreen extends StatelessWidget {
  final List<Product>? initialProducts;
  final Map<int, String>? variantInfoByProductId;

  const BarcodeDesignScreen({
    super.key,
    this.initialProducts,
    this.variantInfoByProductId,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => sl<BarcodeDesignBloc>()
        ..add(
          LoadBarcodeDesignData(
            initialProducts: initialProducts,
            variantInfoByProductId: variantInfoByProductId,
          ),
        ),
      child: const _BarcodeDesignScreenContent(),
    );
  }
}

class _BarcodeDesignScreenContent extends StatelessWidget {
  const _BarcodeDesignScreenContent();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/products');
            }
          },
          tooltip: 'common.back'.tr(),
        ),
        title: Text('barcode.design_title'.tr()),
        centerTitle: true,
        actions: [
          BlocBuilder<BarcodeDesignBloc, RealtimeState<BarcodeDesignData>>(
            builder: (context, state) {
              final data = _extractData(state);
              final hasProducts = data?.selectedProducts.isNotEmpty ?? false;
              final isProcessing = data?.operationStatus == PrintOperationStatus.preparing ||
                  data?.operationStatus == PrintOperationStatus.printing;

              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(LucideIcons.share2),
                    onPressed: hasProducts && !isProcessing
                        ? () => context.read<BarcodeDesignBloc>().add(const ShareLabels())
                        : null,
                    tooltip: 'common.share'.tr(),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.printer),
                    onPressed: hasProducts && !isProcessing
                        ? () => context.read<BarcodeDesignBloc>().add(const PrintLabels())
                        : null,
                    tooltip: 'common.print'.tr(),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: BlocConsumer<BarcodeDesignBloc, RealtimeState<BarcodeDesignData>>(
          listener: (context, state) {
            if (state is RealtimeSuccess<BarcodeDesignData>) {
              final data = state.data;
              if (data.operationStatus == PrintOperationStatus.success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('barcode.print_success'.tr()),
                    backgroundColor: colorScheme.primary,
                  ),
                );
                context.read<BarcodeDesignBloc>().add(const AcknowledgePrintResult());
              } else if (data.operationStatus == PrintOperationStatus.error &&
                  data.errorMessage != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(data.errorMessage!),
                    backgroundColor: colorScheme.error,
                  ),
                );
                context.read<BarcodeDesignBloc>().add(const AcknowledgePrintResult());
              }
            }
          },
          builder: (context, state) {
            if (state is RealtimeLoading<BarcodeDesignData>) {
              return const Center(child: CircularProgressIndicator());
            }

            if (state is RealtimeError<BarcodeDesignData>) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.alertCircle, size: 64, color: colorScheme.error),
                    const SizedBox(height: 16),
                    Text(
                      'common.error'.tr(),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text('barcode.unexpected_error'.tr()),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () => context
                          .read<BarcodeDesignBloc>()
                          .add(const LoadBarcodeDesignData()),
                      child: Text('common.retry'.tr()),
                    ),
                  ],
                ),
              );
            }

            final data = _extractData(state) ?? BarcodeDesignData.empty();

            return LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 600) {
                  return _MobileLayout(data: data);
                } else if (constraints.maxWidth < 1024) {
                  return _TabletLayout(data: data);
                } else {
                  return _DesktopLayout(data: data);
                }
              },
            );
          },
        ),
      ),
    );
  }

  BarcodeDesignData? _extractData(RealtimeState<BarcodeDesignData> state) {
    if (state is RealtimeSuccess<BarcodeDesignData>) {
      return state.data;
    } else if (state is RealtimeLoading<BarcodeDesignData>) {
      return state.previousData;
    } else if (state is RealtimeError<BarcodeDesignData>) {
      return state.previousData;
    }
    return null;
  }
}

/// Mobile layout - vertical stack with bottom sheet for settings
class _MobileLayout extends StatelessWidget {
  final BarcodeDesignData data;

  const _MobileLayout({required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Product selection summary
        _ProductSelectionSummary(data: data),
        
        // Template selector (horizontal scroll) - Fixed height
        if (data.templates.isNotEmpty)
          SizedBox(
            height: 100,
            child: TemplateSelectorWidget(
              templates: data.templates,
              selectedTemplate: data.selectedTemplate,
              onSelect: (template) => context
                  .read<BarcodeDesignBloc>()
                  .add(SelectTemplate(template)),
            ),
          ),

        // Preview area - Flexible to fill available space
        Expanded(
          child: SingleChildScrollView(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: data.selectedProducts.isNotEmpty
                    ? BarcodePreviewWidget(
                        product: data.selectedProducts.first,
                        settings: data.settings,
                        companyProfile: data.companyProfile,
                        variantInfo: data.variantInfoByProductId[data.selectedProducts.first.id],
                      )
                    : _EmptyPreview(),
              ),
            ),
          ),
        ),

        // Settings panel - Scrollable
        Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.4,
          ),
          child: Card(
            margin: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: DesignSettingsWidget(
                settings: data.settings,
                isCompact: true,
              ),
            ),
          ),
        ),

        // Print progress indicator
        if (data.operationStatus == PrintOperationStatus.printing ||
            data.operationStatus == PrintOperationStatus.preparing)
          LinearProgressIndicator(value: data.progress),
      ],
    );
  }
}

/// Tablet layout - side panel with preview
class _TabletLayout extends StatelessWidget {
  final BarcodeDesignData data;

  const _TabletLayout({required this.data});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Left sidebar - Products and templates
        SizedBox(
          width: 280,
          child: Column(
            children: [
              // Product selection
              Expanded(
                flex: 2,
                child: ProductSelectionWidget(
                  selectedProducts: data.selectedProducts.cast<Product>(),
                  onRemove: (productId) => context
                      .read<BarcodeDesignBloc>()
                      .add(RemoveProductFromSelection(productId)),
                  onClear: () => context
                      .read<BarcodeDesignBloc>()
                      .add(const ClearProductSelection()),
                ),
              ),
              const Divider(height: 1),
              // Templates - compact cards (same as mobile/desktop)
              if (data.templates.isNotEmpty)
                SizedBox(
                  height: 100,
                  child: TemplateSelectorWidget(
                    templates: data.templates,
                    selectedTemplate: data.selectedTemplate,
                    onSelect: (template) => context
                        .read<BarcodeDesignBloc>()
                        .add(SelectTemplate(template)),
                  ),
                ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        // Main content - Preview
        Expanded(
          flex: 2,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: data.selectedProducts.isNotEmpty
                          ? BarcodePreviewWidget(
                              product: data.selectedProducts.first,
                              settings: data.settings,
                              companyProfile: data.companyProfile,
                              variantInfo: data.variantInfoByProductId[data.selectedProducts.first.id],
                              scale: 1.5,
                            )
                          : _EmptyPreview(),
                    ),
                  ),
                ),
              ),
              if (data.operationStatus == PrintOperationStatus.printing ||
                  data.operationStatus == PrintOperationStatus.preparing)
                LinearProgressIndicator(value: data.progress),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        // Right panel - Settings
        SizedBox(
          width: 300,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: DesignSettingsWidget(
              settings: data.settings,
              isCompact: false,
            ),
          ),
        ),
      ],
    );
  }
}

/// Desktop layout - full canvas with advanced controls
class _DesktopLayout extends StatelessWidget {
  final BarcodeDesignData data;

  const _DesktopLayout({required this.data});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Left sidebar - Product browser
        SizedBox(
          width: 320,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'barcode.selected_products'.tr(),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Expanded(
                child: ProductSelectionWidget(
                  selectedProducts: data.selectedProducts.cast<Product>(),
                  onRemove: (productId) => context
                      .read<BarcodeDesignBloc>()
                      .add(RemoveProductFromSelection(productId)),
                  onClear: () => context
                      .read<BarcodeDesignBloc>()
                      .add(const ClearProductSelection()),
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        // Center - Canvas preview
        Expanded(
          flex: 3,
          child: Column(
            children: [
              // Template selector bar - Fixed height with horizontal scroll
              Container(
                height: 90,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TemplateSelectorWidget(
                  templates: data.templates,
                  selectedTemplate: data.selectedTemplate,
                  onSelect: (template) => context
                      .read<BarcodeDesignBloc>()
                      .add(SelectTemplate(template)),
                ),
              ),
              const Divider(height: 1),
              // Preview canvas - Scrollable
              Expanded(
                child: Container(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: SingleChildScrollView(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: data.selectedProducts.isNotEmpty
                            ? BarcodePreviewWidget(
                                product: data.selectedProducts.first,
                                settings: data.settings,
                                companyProfile: data.companyProfile,
                                variantInfo: data.variantInfoByProductId[data.selectedProducts.first.id],
                                scale: 2.0,
                              )
                            : _EmptyPreview(),
                      ),
                    ),
                  ),
                ),
              ),
              if (data.operationStatus == PrintOperationStatus.printing ||
                  data.operationStatus == PrintOperationStatus.preparing)
                LinearProgressIndicator(value: data.progress),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        // Right panel - Advanced settings
        SizedBox(
          width: 360,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'barcode.settings'.tr(),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                DesignSettingsWidget(
                  settings: data.settings,
                  isCompact: false,
                ),
                const SizedBox(height: 24),
                _PrintActionsWidget(data: data),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Empty preview placeholder
class _EmptyPreview extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          LucideIcons.scan,
          size: 64,
          color: colorScheme.outline,
        ),
        const SizedBox(height: 16),
        Text(
          'barcode.no_product_selected'.tr(),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: colorScheme.outline,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'barcode.select_product_hint'.tr(),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.outline,
              ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// Product selection summary for mobile
class _ProductSelectionSummary extends StatelessWidget {
  final BarcodeDesignData data;

  const _ProductSelectionSummary({required this.data});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final count = data.selectedProducts.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Icon(LucideIcons.package, size: 20, color: colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              count == 0
                  ? 'barcode.no_products'.tr()
                  : 'barcode.products_selected'.tr(args: [count.toString()]),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          if (count > 0)
            TextButton(
              onPressed: () => context
                  .read<BarcodeDesignBloc>()
                  .add(const ClearProductSelection()),
              child: Text('common.clear'.tr()),
            ),
        ],
      ),
    );
  }
}

/// Print actions widget for desktop
class _PrintActionsWidget extends StatelessWidget {
  final BarcodeDesignData data;

  const _PrintActionsWidget({required this.data});

  @override
  Widget build(BuildContext context) {
    final hasProducts = data.selectedProducts.isNotEmpty;
    final isProcessing = data.operationStatus == PrintOperationStatus.preparing ||
        data.operationStatus == PrintOperationStatus.printing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'barcode.actions'.tr(),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: hasProducts && !isProcessing
              ? () => context.read<BarcodeDesignBloc>().add(const PrintLabels())
              : null,
          icon: isProcessing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(LucideIcons.printer),
          label: Text(
            isProcessing ? 'barcode.printing'.tr() : 'barcode.print_labels'.tr(),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: hasProducts && !isProcessing
              ? () => context.read<BarcodeDesignBloc>().add(const ShareLabels())
              : null,
          icon: const Icon(LucideIcons.share2),
          label: Text('barcode.share_pdf'.tr()),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: hasProducts
              ? () => _showSaveTemplateDialog(context)
              : null,
          icon: const Icon(LucideIcons.save),
          label: Text('barcode.save_template'.tr()),
        ),
      ],
    );
  }

  void _showSaveTemplateDialog(BuildContext context) {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('barcode.save_template'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'barcode.template_name'.tr(),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descController,
              decoration: InputDecoration(
                labelText: 'barcode.template_description'.tr(),
                border: const OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () {
              if (nameController.text.trim().isNotEmpty) {
                context.read<BarcodeDesignBloc>().add(
                      SaveAsTemplate(
                        name: nameController.text.trim(),
                        description: descController.text.trim().isEmpty
                            ? null
                            : descController.text.trim(),
                      ),
                    );
                Navigator.of(dialogContext).pop();
              }
            },
            child: Text('common.save'.tr()),
          ),
        ],
      ),
    );
  }
}
