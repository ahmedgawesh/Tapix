import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:mobile_scanner/mobile_scanner.dart' as mobile_scanner;

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../products/domain/entities/product_entity.dart';
import '../../domain/entities/scanner_result.dart';
import '../bloc/barcode_scanner_bloc.dart';
import '../widgets/product_result_card.dart';
import '../widgets/manual_barcode_dialog.dart';

class BarcodeScannerScreen extends StatelessWidget {
  final bool returnOnScan;

  const BarcodeScannerScreen({super.key, this.returnOnScan = false});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => sl<BarcodeScannerBloc>()..add(const StartScanning()),
      child: _BarcodeScannerView(returnOnScan: returnOnScan),
    );
  }
}

class _BarcodeScannerView extends StatefulWidget {
  final bool returnOnScan;
  const _BarcodeScannerView({this.returnOnScan = false});

  @override
  State<_BarcodeScannerView> createState() => _BarcodeScannerViewState();
}

class _BarcodeScannerViewState extends State<_BarcodeScannerView> {
  mobile_scanner.MobileScannerController? _controller;
  bool _isFlashOn = false;
  bool _isFrontCamera = false;
  bool _isDesktop = false;

  @override
  void initState() {
    super.initState();
    _checkPlatform();
    if (!_isDesktop) {
      _initController();
    }
  }

  void _checkPlatform() {
    if (kIsWeb) {
      _isDesktop = false; // Web can use camera
    } else {
      _isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    }
  }

  void _initController() {
    _controller = mobile_scanner.MobileScannerController(
      detectionSpeed: mobile_scanner.DetectionSpeed.normal,
      facing: mobile_scanner.CameraFacing.back,
      torchEnabled: false,
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onBarcodeDetected(mobile_scanner.BarcodeCapture capture) {
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final barcode = barcodes.first;
    if (barcode.rawValue == null) return;

    final format = _mapBarcodeFormat(barcode.format);
    
    // Provide haptic feedback
    HapticFeedback.mediumImpact();

    if (widget.returnOnScan) {
      _controller?.stop();
      context.pop(barcode.rawValue);
      return;
    }

    context.read<BarcodeScannerBloc>().add(BarcodeDetected(
      barcode: barcode.rawValue!,
      format: format,
    ));

    // Pause scanning after detection
    _controller?.stop();
  }

  BarcodeFormat _mapBarcodeFormat(mobile_scanner.BarcodeFormat format) {
    switch (format) {
      case mobile_scanner.BarcodeFormat.ean13:
        return BarcodeFormat.ean13;
      case mobile_scanner.BarcodeFormat.ean8:
        return BarcodeFormat.ean8;
      case mobile_scanner.BarcodeFormat.upcA:
        return BarcodeFormat.upcA;
      case mobile_scanner.BarcodeFormat.upcE:
        return BarcodeFormat.upcE;
      case mobile_scanner.BarcodeFormat.code128:
        return BarcodeFormat.code128;
      case mobile_scanner.BarcodeFormat.code39:
        return BarcodeFormat.code39;
      case mobile_scanner.BarcodeFormat.qrCode:
        return BarcodeFormat.qrCode;
      default:
        return BarcodeFormat.unknown;
    }
  }

  void _toggleFlash() async {
    await _controller?.toggleTorch();
    setState(() {
      _isFlashOn = !_isFlashOn;
    });
  }

  void _switchCamera() async {
    await _controller?.switchCamera();
    setState(() {
      _isFrontCamera = !_isFrontCamera;
    });
  }

  void _resumeScanning() {
    context.read<BarcodeScannerBloc>().add(const ClearScanResult());
    _controller?.start();
  }

  void _showManualEntryDialog() async {
    final barcode = await showDialog<String>(
      context: context,
      builder: (context) => const ManualBarcodeDialog(),
    );

    if (barcode != null && barcode.isNotEmpty && mounted) {
      context.read<BarcodeScannerBloc>().add(ManualBarcodeEntered(barcode));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/products');
            }
          },
          tooltip: 'common.back'.tr(),
        ),
        title: Text('barcode.scanner_title'.tr()),
        centerTitle: true,
        actions: _isDesktop ? null : [
          IconButton(
            icon: Icon(_isFlashOn ? LucideIcons.zapOff : LucideIcons.zap),
            onPressed: _toggleFlash,
            tooltip: 'barcode.toggle_flash'.tr(),
          ),
          IconButton(
            icon: Icon(_isFrontCamera ? LucideIcons.camera : LucideIcons.flipHorizontal),
            onPressed: _switchCamera,
            tooltip: 'barcode.switch_camera'.tr(),
          ),
        ],
      ),
      body: BlocBuilder<BarcodeScannerBloc, RealtimeState<ScannerState>>(
        builder: (context, state) {
          if (state is! RealtimeSuccess<ScannerState>) {
            return const Center(child: CircularProgressIndicator());
          }

          final scannerState = state.data;

          // Desktop mode - show manual entry UI
          if (_isDesktop) {
            return _buildDesktopManualEntryUI(context, scannerState);
          }

          // Mobile mode - show camera scanner
          return Column(
            children: [
              // Camera preview
              Expanded(
                flex: 2,
                child: Stack(
                  children: [
                    // Camera view
                    ClipRRect(
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(24),
                        bottomRight: Radius.circular(24),
                      ),
                      child: mobile_scanner.MobileScanner(
                        controller: _controller,
                        onDetect: _onBarcodeDetected,
                        errorBuilder: (context, error) {
                          return _buildCameraError(context, error);
                        },
                      ),
                    ),
                    // Scan overlay
                    _buildScanOverlay(context),
                    // Status indicator
                    if (scannerState.isSearching)
                      Positioned(
                        top: 16,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.surface.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                                const SizedBox(width: 8),
                                Text('barcode.searching'.tr()),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Results section
              Expanded(
                flex: 1,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  child: _buildResultSection(context, scannerState),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: _isDesktop ? null : FloatingActionButton.extended(
        onPressed: _showManualEntryDialog,
        icon: const Icon(LucideIcons.keyboard),
        label: Text('barcode.manual_entry'.tr()),
      ),
    );
  }

  Widget _buildDesktopManualEntryUI(BuildContext context, ScannerState scannerState) {
    final colorScheme = Theme.of(context).colorScheme;
    final textController = TextEditingController();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                LucideIcons.monitor,
                size: 64,
                color: colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'barcode.desktop_mode_title'.tr(),
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'barcode.desktop_mode_description'.tr(),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              TextField(
                controller: textController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'barcode.barcode_label'.tr(),
                  hintText: 'barcode.barcode_hint'.tr(),
                  prefixIcon: const Icon(LucideIcons.scan),
                  border: const OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (value) {
                  if (value.isNotEmpty) {
                    context.read<BarcodeScannerBloc>().add(ManualBarcodeEntered(value));
                    textController.clear();
                  }
                },
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    final value = textController.text;
                    if (value.isNotEmpty) {
                      context.read<BarcodeScannerBloc>().add(ManualBarcodeEntered(value));
                      textController.clear();
                    }
                  },
                  icon: const Icon(LucideIcons.search),
                  label: Text('barcode.search_product'.tr()),
                ),
              ),
              const SizedBox(height: 32),
              Expanded(
                child: _buildResultSection(context, scannerState),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraError(BuildContext context, mobile_scanner.MobileScannerException error) {
    final colorScheme = Theme.of(context).colorScheme;

    String errorMessage;
    switch (error.errorCode) {
      case mobile_scanner.MobileScannerErrorCode.permissionDenied:
        errorMessage = 'barcode.error_permission_denied'.tr();
        break;
      case mobile_scanner.MobileScannerErrorCode.unsupported:
        errorMessage = 'barcode.error_unsupported'.tr();
        break;
      default:
        errorMessage = 'barcode.error_camera'.tr();
    }

    return Container(
      color: colorScheme.surface,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.cameraOff,
              size: 64,
              color: colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              errorMessage,
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.error),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _showManualEntryDialog,
              child: Text('barcode.use_manual_entry'.tr()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanOverlay(BuildContext context) {
    return CustomPaint(
      painter: ScanOverlayPainter(
        borderColor: Theme.of(context).colorScheme.primary,
        overlayColor: Colors.black.withValues(alpha: 0.5),
      ),
      child: const SizedBox.expand(),
    );
  }

  Widget _buildResultSection(BuildContext context, ScannerState state) {
    final colorScheme = Theme.of(context).colorScheme;

    // Show error if any
    if (state.error != null) {
      return _buildErrorCard(context, state.error!);
    }

    // Show found product
    if (state.foundProduct != null) {
      return _buildProductFound(context, state.foundProduct!, state.lastResult);
    }

    // Show not found if we have a result but no product
    if (state.lastResult != null && !state.isSearching) {
      return _buildProductNotFound(context, state.lastResult!);
    }

    // Show instructions
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.scan,
            size: 48,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'barcode.scan_instructions'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(BuildContext context, String error) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      color: colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.alertTriangle,
              color: colorScheme.onErrorContainer,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onErrorContainer),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _resumeScanning,
              child: Text('barcode.scan_again'.tr()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductFound(
    BuildContext context,
    Product product,
    ScannerResult? scanResult,
  ) {
    return Column(
      children: [
        Expanded(
          child: ProductResultCard(
            product: product,
            scanResult: scanResult,
            onViewProduct: () {
              context.push('/products/${product.id}/edit');
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _resumeScanning,
                icon: const Icon(LucideIcons.scan),
                label: Text('barcode.scan_again'.tr()),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProductNotFound(BuildContext context, ScannerResult scanResult) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.packageX,
                color: colorScheme.onSurfaceVariant,
                size: 32,
              ),
              const SizedBox(height: 8),
              Text(
                'barcode.product_not_found'.tr(),
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                scanResult.barcode,
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontFamily: 'monospace',
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _resumeScanning,
                    icon: const Icon(LucideIcons.scan, size: 18),
                    label: Text('barcode.scan_again'.tr()),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      context.push('/products/new', extra: {'barcode': scanResult.barcode});
                    },
                    icon: const Icon(LucideIcons.plus, size: 18),
                    label: Text('barcode.create_product'.tr()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ScanOverlayPainter extends CustomPainter {
  final Color borderColor;
  final Color overlayColor;

  ScanOverlayPainter({
    required this.borderColor,
    required this.overlayColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scanAreaSize = size.width * 0.7;
    final left = (size.width - scanAreaSize) / 2;
    final top = (size.height - scanAreaSize) / 2;
    final scanRect = Rect.fromLTWH(left, top, scanAreaSize, scanAreaSize);

    // Draw overlay
    final overlayPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(scanRect, const Radius.circular(16)))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(
      overlayPath,
      Paint()..color = overlayColor,
    );

    // Draw corner brackets
    const cornerLength = 30.0;
    const cornerWidth = 4.0;
    final paint = Paint()
      ..color = borderColor
      ..strokeWidth = cornerWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Top-left corner
    canvas.drawLine(
      Offset(left, top + cornerLength),
      Offset(left, top),
      paint,
    );
    canvas.drawLine(
      Offset(left, top),
      Offset(left + cornerLength, top),
      paint,
    );

    // Top-right corner
    canvas.drawLine(
      Offset(left + scanAreaSize - cornerLength, top),
      Offset(left + scanAreaSize, top),
      paint,
    );
    canvas.drawLine(
      Offset(left + scanAreaSize, top),
      Offset(left + scanAreaSize, top + cornerLength),
      paint,
    );

    // Bottom-left corner
    canvas.drawLine(
      Offset(left, top + scanAreaSize - cornerLength),
      Offset(left, top + scanAreaSize),
      paint,
    );
    canvas.drawLine(
      Offset(left, top + scanAreaSize),
      Offset(left + cornerLength, top + scanAreaSize),
      paint,
    );

    // Bottom-right corner
    canvas.drawLine(
      Offset(left + scanAreaSize - cornerLength, top + scanAreaSize),
      Offset(left + scanAreaSize, top + scanAreaSize),
      paint,
    );
    canvas.drawLine(
      Offset(left + scanAreaSize, top + scanAreaSize - cornerLength),
      Offset(left + scanAreaSize, top + scanAreaSize),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
