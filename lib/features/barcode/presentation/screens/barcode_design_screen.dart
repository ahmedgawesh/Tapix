import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../products/domain/entities/product_entity.dart';
import '../../domain/models/barcode_design_state.dart';
import '../../data/models/invoice_print_data.dart';
import '../../services/barcode_label_job_builder.dart';
import '../../services/barcode_printer_service.dart';
import '../bloc/barcode_design_bloc.dart';
import '../bloc/barcode_design_event.dart';
import '../widgets/a4_preview_widget.dart';
import '../widgets/design_settings_widget.dart';
import '../widgets/product_selection_widget.dart';
import '../widgets/thermal_preview_widget.dart';

Future<void> _startBarcodePrint(
  BuildContext context,
  BarcodeDesignData data,
) async {
  final bloc = context.read<BarcodeDesignBloc>();
  if (data.settings.printDestination == PrintDestination.system) {
    bloc.add(const PrintLabels());
    return;
  }

  final printerService = sl<BarcodePrinterService>();
  if (!printerService.isBluetoothPrintingSupported) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('barcode.bluetooth_android_only'.tr())),
    );
    return;
  }

  try {
    final devices = await printerService.getBondedBluetoothPrinters();
    if (!context.mounted) return;
    if (devices.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('barcode.no_bluetooth_printers'.tr()),
          content: Text('barcode.pair_printer_first'.tr()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('common.ok'.tr()),
            ),
          ],
        ),
      );
      return;
    }

    final selected = await showDialog<BluetoothPrinterDevice>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('barcode.select_bluetooth_printer'.tr()),
        children: devices
            .map(
              (device) => SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, device),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.bluetooth),
                  title: Text(device.name),
                  subtitle: Text(device.address),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
    if (selected == null || !context.mounted) return;
    bloc.add(
      PrintLabels(
        printerName: selected.name,
        bluetoothAddress: selected.address,
      ),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_localizedBluetoothError(error))));
  }
}

String _localizedBluetoothError(Object error) {
  if (error is PlatformException) {
    switch (error.code) {
      case 'bluetooth_disabled':
        return 'barcode.bluetooth_disabled'.tr();
      case 'bluetooth_permission_denied':
        return 'barcode.bluetooth_permission_denied'.tr();
      case 'bluetooth_unavailable':
        return 'barcode.bluetooth_unavailable'.tr();
      case 'bluetooth_print_failed':
        return 'barcode.bluetooth_connection_failed'.tr();
    }
  }
  return 'barcode.bluetooth_error'.tr(args: [error.toString()]);
}

class BarcodeDesignScreen extends StatelessWidget {
  final List<Product>? initialProducts;
  final Map<int, String>? variantInfoByProductId;
  final Set<int>? selectedVariantIds;
  final InvoicePrintData? invoiceData;

  const BarcodeDesignScreen({
    super.key,
    this.initialProducts,
    this.variantInfoByProductId,
    this.selectedVariantIds,
    this.invoiceData,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final bloc = sl<BarcodeDesignBloc>()
          ..add(
            LoadBarcodeDesignData(
              initialProducts: initialProducts,
              variantInfoByProductId: variantInfoByProductId,
              selectedVariantIds: selectedVariantIds,
            ),
          );

        final invoice = invoiceData;
        if (invoice != null) {
          bloc.add(LoadInvoicePrintData(invoice));
        }
        return bloc;
      },
      child: const _BarcodeDesignScreenContent(),
    );
  }
}

class _BarcodeDesignScreenContent extends StatelessWidget {
  const _BarcodeDesignScreenContent();

  void _showSnackBarSafe(BuildContext context, SnackBar snackBar) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      messenger.clearSnackBars();
      messenger.showSnackBar(snackBar);
    });
  }

  Future<List<({Product product, String? variantInfo})>> _buildPreviewLabels(
    BarcodeDesignData data,
  ) async {
    final jobs = await BarcodeLabelJobBuilder(sl()).build(
      selectedProducts: data.selectedProducts,
      settings: data.settings,
      variantInfoByProductId: data.variantInfoByProductId,
      selectedVariantIds: data.selectedVariantIds,
      invoiceData: data.invoiceData,
      currentQuantities: data.currentQuantities,
    );
    final labels = <({Product product, String? variantInfo})>[];
    for (final job in jobs) {
      for (int i = 0; i < job.copies; i++) {
        labels.add((product: job.product, variantInfo: job.variantInfo));
      }
    }
    return labels;
  }

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
              final isProcessing =
                  data?.operationStatus == PrintOperationStatus.preparing ||
                  data?.operationStatus == PrintOperationStatus.printing;

              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(LucideIcons.share2),
                    onPressed: hasProducts && !isProcessing
                        ? () => context.read<BarcodeDesignBloc>().add(
                            const ShareLabels(),
                          )
                        : null,
                    tooltip: 'common.share'.tr(),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.printer),
                    onPressed: hasProducts && !isProcessing
                        ? () => _startBarcodePrint(context, data!)
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
        child:
            BlocConsumer<BarcodeDesignBloc, RealtimeState<BarcodeDesignData>>(
              listenWhen: (previous, current) {
                final prevData = _extractData(previous);
                final currData = _extractData(current);

                final prevError = prevData?.errorMessage;
                final currError = currData?.errorMessage;
                final errorChanged =
                    currError != null &&
                    currError.isNotEmpty &&
                    currError != prevError;

                final prevStatus = prevData?.operationStatus;
                final currStatus = currData?.operationStatus;
                final statusChanged =
                    currStatus == PrintOperationStatus.success &&
                    prevStatus != currStatus;

                return errorChanged || statusChanged;
              },
              listener: (context, state) {
                if (state is RealtimeSuccess<BarcodeDesignData>) {
                  final data = state.data;

                  if (data.operationStatus == PrintOperationStatus.success) {
                    _showSnackBarSafe(
                      context,
                      SnackBar(
                        content: Text('barcode.print_success'.tr()),
                        backgroundColor: colorScheme.primary,
                      ),
                    );
                    context.read<BarcodeDesignBloc>().add(
                      const AcknowledgePrintResult(),
                    );
                  }

                  if (data.errorMessage != null &&
                      data.errorMessage!.isNotEmpty) {
                    _showSnackBarSafe(
                      context,
                      SnackBar(
                        content: Text(data.errorMessage!),
                        backgroundColor: colorScheme.error,
                      ),
                    );
                    context.read<BarcodeDesignBloc>().add(
                      const AcknowledgePrintResult(),
                    );
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
                        Icon(
                          LucideIcons.alertCircle,
                          size: 64,
                          color: colorScheme.error,
                        ),
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

                if (!data.settings.isA4Mode) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!context.mounted) return;
                    context.read<BarcodeDesignBloc>().add(
                      const UpdatePrintMode(LabelPrintMode.a4Sheet),
                    );
                  });
                }

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

/// Stateful widget that caches the labels Future so it doesn't rebuild infinitely.
class _CachedPrintPreview extends StatefulWidget {
  final BarcodeDesignData data;
  final double a4Scale;
  final double thermalScale;

  const _CachedPrintPreview({
    required this.data,
    required this.a4Scale,
    required this.thermalScale,
  });

  @override
  State<_CachedPrintPreview> createState() => _CachedPrintPreviewState();
}

class _CachedPrintPreviewState extends State<_CachedPrintPreview> {
  Future<List<({Product product, String? variantInfo})>>? _labelsFuture;

  @override
  void initState() {
    super.initState();
    _refreshFuture();
  }

  @override
  void didUpdateWidget(covariant _CachedPrintPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_shouldRefresh(oldWidget.data, widget.data)) {
      _refreshFuture();
    }
  }

  bool _shouldRefresh(BarcodeDesignData oldData, BarcodeDesignData newData) {
    return oldData.selectedProducts != newData.selectedProducts ||
        oldData.settings != newData.settings ||
        oldData.invoiceData != newData.invoiceData ||
        oldData.currentQuantities != newData.currentQuantities ||
        oldData.variantInfoByProductId != newData.variantInfoByProductId ||
        oldData.selectedVariantIds != newData.selectedVariantIds ||
        oldData.companyProfile != newData.companyProfile;
  }

  void _refreshFuture() {
    _labelsFuture = const _BarcodeDesignScreenContent()._buildPreviewLabels(
      widget.data,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<({Product product, String? variantInfo})>>(
      future: _labelsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final labels = snapshot.data ?? const [];
        if (labels.isEmpty) return const _EmptyPreview();
        final showA4 =
            widget.data.settings.printDestination == PrintDestination.system &&
            widget.data.settings.isA4Mode;
        if (showA4) {
          return A4BatchPreviewWidget(
            labels: labels,
            settings: widget.data.settings,
            companyProfile: widget.data.companyProfile,
            scale: widget.a4Scale,
          );
        }
        return ThermalBatchPreviewWidget(
          labels: labels,
          settings: widget.data.settings,
          companyProfile: widget.data.companyProfile,
          scale: widget.thermalScale,
        );
      },
    );
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

        // Preview area - Flexible to fill available space
        Expanded(
          child: InteractiveViewer(
            panEnabled: true,
            scaleEnabled: true,
            constrained: false,
            minScale: 0.5,
            maxScale: 4.0,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: data.selectedProducts.isNotEmpty
                    ? _CachedPrintPreview(
                        data: data,
                        a4Scale: 0.35,
                        thermalScale: 0.9,
                      )
                    : const _EmptyPreview(),
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
                  onClear: () => context.read<BarcodeDesignBloc>().add(
                    const ClearProductSelection(),
                  ),
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
                child: InteractiveViewer(
                  panEnabled: true,
                  scaleEnabled: true,
                  constrained: false,
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: data.selectedProducts.isNotEmpty
                          ? _CachedPrintPreview(
                              data: data,
                              a4Scale: 0.45,
                              thermalScale: 1.2,
                            )
                          : const _EmptyPreview(),
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
                  onClear: () => context.read<BarcodeDesignBloc>().add(
                    const ClearProductSelection(),
                  ),
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
              // Preview canvas - Scrollable
              Expanded(
                child: Container(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: InteractiveViewer(
                    panEnabled: true,
                    scaleEnabled: true,
                    constrained: false,
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: data.selectedProducts.isNotEmpty
                            ? _CachedPrintPreview(
                                data: data,
                                a4Scale: 0.6,
                                thermalScale: 1.6,
                              )
                            : const _EmptyPreview(),
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
                DesignSettingsWidget(settings: data.settings, isCompact: false),
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
  const _EmptyPreview();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(LucideIcons.scan, size: 64, color: colorScheme.outline),
        const SizedBox(height: 16),
        Text(
          'barcode.no_product_selected'.tr(),
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: colorScheme.outline),
        ),
        const SizedBox(height: 8),
        Text(
          'barcode.select_product_hint'.tr(),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colorScheme.outline),
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
              onPressed: () => context.read<BarcodeDesignBloc>().add(
                const ClearProductSelection(),
              ),
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
    final isProcessing =
        data.operationStatus == PrintOperationStatus.preparing ||
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
              ? () => _startBarcodePrint(context, data)
              : null,
          icon: isProcessing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(LucideIcons.printer),
          label: Text(
            isProcessing
                ? 'barcode.printing'.tr()
                : 'barcode.print_labels'.tr(),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: hasProducts
              ? () => context.read<BarcodeDesignBloc>().add(const ShareLabels())
              : null,
          icon: const Icon(LucideIcons.share2),
          label: Text('barcode.share_pdf'.tr()),
        ),
      ],
    );
  }
}
