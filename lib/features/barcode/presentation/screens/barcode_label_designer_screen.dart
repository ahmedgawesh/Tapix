import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../../../../features/products/domain/entities/product_entity.dart';
import '../../../settings/presentation/bloc/app_settings_bloc.dart';
import '../../services/barcode_printer_service.dart';

class BarcodeLabelDesignerScreen extends StatefulWidget {
  final Product product;

  const BarcodeLabelDesignerScreen({super.key, required this.product});

  @override
  State<BarcodeLabelDesignerScreen> createState() =>
      _BarcodeLabelDesignerScreenState();
}

class _BarcodeLabelDesignerScreenState
    extends State<BarcodeLabelDesignerScreen> {
  final _printerService = sl<BarcodePrinterService>();
  final _currencyService = sl<CurrencyService>();

  bool _isLoading = true;
  double _labelWidth = 58;
  double _labelHeight = 40;
  bool _includePrice = true;
  bool _includeName = true;
  int _copies = 1;
  String _selectedBarcodeType = 'Auto'; // Auto, Code128, EAN13, EAN8, UPCA, QR

  final List<String> _barcodeTypes = [
    'Auto',
    'Code 128',
    'EAN-13',
    'EAN-8',
    'UPC-A',
    'QR Code',
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      // Read AppSettings defaults first
      final appSettings = context.read<AppSettingsBloc>().state.settings;
      _labelWidth = appSettings.labelWidthMm;
      _labelHeight = appSettings.labelHeightMm;
      _includePrice = appSettings.includePriceOnLabel;
      _includeName = true; // always default to true

      // Override with any previously saved per-session settings
      final config = await _printerService.getSettings();
      if (config.includeName != null) _includeName = config.includeName!;
      if (config.includePrice != null) _includePrice = config.includePrice!;

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Barcode _getBarcodeType(String data) {
    switch (_selectedBarcodeType) {
      case 'Code 128':
        return Barcode.code128();
      case 'EAN-13':
        return Barcode.ean13();
      case 'EAN-8':
        return Barcode.ean8();
      case 'UPC-A':
        return Barcode.upcA();
      case 'QR Code':
        return Barcode.qrCode();
      case 'Auto':
      default:
        // Check for EAN-13 (13 digits)
        if (data.length == 13 && int.tryParse(data) != null) {
          return Barcode.ean13();
        }
        // Check for EAN-8 (8 digits)
        if (data.length == 8 && int.tryParse(data) != null) {
          return Barcode.ean8();
        }
        // Check for UPC-A (12 digits)
        if (data.length == 12 && int.tryParse(data) != null) {
          return Barcode.upcA();
        }
        // Fallback to Code 128 for everything else
        return Barcode.code128();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final barcodeData = widget.product.barcode ?? '';
    final barcodeType = _getBarcodeType(barcodeData);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text('barcode.label_designer'.tr()),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.share2),
            onPressed: () => _shareLabel(barcodeType),
            tooltip: 'common.share'.tr(),
          ),
          IconButton(
            icon: const Icon(LucideIcons.printer),
            onPressed: () => _printLabel(barcodeType),
            tooltip: 'common.print'.tr(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Preview Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text(
                      'barcode.preview'.tr(),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width:
                          _labelWidth *
                          3.78, // Approx px conversion (1mm ~= 3.78px)
                      height: _labelHeight * 3.78,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(8),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final contentHeight = constraints.maxHeight.clamp(
                            1.0,
                            double.infinity,
                          );

                          final nameLine = _includeName ? 16.0 : 0.0;
                          final priceLine = _includePrice ? 18.0 : 0.0;
                          final gaps =
                              (_includeName ? 4.0 : 0.0) +
                              (_includePrice ? 4.0 : 0.0);

                          final barcodeHeight =
                              (contentHeight - nameLine - priceLine - gaps)
                                  .clamp(8.0, contentHeight);

                          return FittedBox(
                            fit: BoxFit.scaleDown,
                            child: SizedBox(
                              width: constraints.maxWidth,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_includeName)
                                    Text(
                                      widget.product.name,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                    ),
                                  if (_includeName) const SizedBox(height: 4),
                                  if (barcodeData.isNotEmpty)
                                    SizedBox(
                                      height: barcodeHeight,
                                      child: BarcodeWidget(
                                        barcode: barcodeType,
                                        data: barcodeData,
                                        drawText: true,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.black,
                                        ),
                                        errorBuilder: (context, error) =>
                                            Center(
                                              child: Text(
                                                error,
                                                style: const TextStyle(
                                                  color: Colors.red,
                                                  fontSize: 10,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                            ),
                                      ),
                                    ),
                                  if (_includePrice) const SizedBox(height: 4),
                                  if (_includePrice)
                                    Text(
                                      _currencyService.format(
                                        widget.product.priceCents
                                            .toBigInt()
                                            .toInt(),
                                      ),
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Settings
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'barcode.settings'.tr(),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    // Copies
                    Row(
                      children: [
                        Expanded(child: Text('barcode.copies'.tr())),
                        IconButton(
                          icon: const Icon(LucideIcons.minus),
                          onPressed: () {
                            if (_copies > 1) setState(() => _copies--);
                          },
                        ),
                        Text(
                          '$_copies',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(LucideIcons.plus),
                          onPressed: () => setState(() => _copies++),
                        ),
                      ],
                    ),
                    const Divider(),
                    // Barcode Type
                    DropdownButtonFormField<String>(
                      // ignore: deprecated_member_use
                      value: _selectedBarcodeType,
                      decoration: InputDecoration(
                        labelText: 'barcode.type'.tr(),
                        border: const OutlineInputBorder(),
                      ),
                      items: _barcodeTypes.map((type) {
                        return DropdownMenuItem(value: type, child: Text(type));
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedBarcodeType = value);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: _labelWidth.toString(),
                            decoration: InputDecoration(
                              labelText: 'barcode.width_mm'.tr(),
                              border: const OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (v) => setState(
                              () => _labelWidth = double.tryParse(v) ?? 58,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            initialValue: _labelHeight.toString(),
                            decoration: InputDecoration(
                              labelText: 'barcode.height_mm'.tr(),
                              border: const OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (v) => setState(
                              () => _labelHeight = double.tryParse(v) ?? 40,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: Text('barcode.include_name'.tr()),
                      value: _includeName,
                      onChanged: (v) => setState(() => _includeName = v),
                    ),
                    SwitchListTile(
                      title: Text('barcode.include_price'.tr()),
                      value: _includePrice,
                      onChanged: (v) => setState(() => _includePrice = v),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _printLabel(Barcode barcodeType) async {
    final barcodeData = widget.product.barcode;
    if (barcodeData == null || barcodeData.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('barcode.error_no_barcode'.tr())));
      return;
    }

    try {
      // Validate barcode data
      if (!barcodeType.isValid(barcodeData)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'barcode.error_invalid_format'.tr(
                args: [barcodeType.name, barcodeData],
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Save settings before printing
      await _printerService.saveSettings(
        widthMm: _labelWidth,
        heightMm: _labelHeight,
      );

      await _printerService.printLabel(
        product: widget.product,
        barcode: barcodeType,
        widthMm: _labelWidth,
        heightMm: _labelHeight,
        includeName: _includeName,
        includePrice: _includePrice,
        includeBarcode: true,
        copies: _copies,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('barcode.print_error'.tr(args: [e.toString()])),
          ),
        );
      }
    }
  }

  Future<void> _shareLabel(Barcode barcodeType) async {
    final barcodeData = widget.product.barcode;
    if (barcodeData == null || barcodeData.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('barcode.error_no_barcode'.tr())));
      return;
    }

    try {
      // Validate barcode data
      if (!barcodeType.isValid(barcodeData)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'barcode.error_invalid_format'.tr(
                args: [barcodeType.name, barcodeData],
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      await _printerService.shareLabelPdf(
        product: widget.product,
        barcode: barcodeType,
        widthMm: _labelWidth,
        heightMm: _labelHeight,
        includeName: _includeName,
        includePrice: _includePrice,
        includeBarcode: true,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('barcode.share_error'.tr(args: [e.toString()])),
          ),
        );
      }
    }
  }
}
