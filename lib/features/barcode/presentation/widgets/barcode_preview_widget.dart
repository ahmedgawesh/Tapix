import 'package:barcode_widget/barcode_widget.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../../../products/domain/entities/product_entity.dart';
import '../../../settings/domain/entities/company_profile.dart';
import '../../domain/models/barcode_design_state.dart';
import '../../services/barcode_printer_service.dart';

class BarcodePreviewWidget extends StatelessWidget {
  final Product product;
  final BarcodeDesignSettings settings;
  final CompanyProfile companyProfile;
  final String? variantInfo;
  final double scale;

  const BarcodePreviewWidget({
    super.key,
    required this.product,
    required this.settings,
    required this.companyProfile,
    this.variantInfo,
    this.scale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final printerService = sl<BarcodePrinterService>();
    final currencyService = sl<CurrencyService>();
    final barcodeData = product.barcode ?? '';
    final barcodeType = printerService.getBarcodeTypeAuto(barcodeData, settings.barcodeType);
    final fallbackBarcodeType = printerService.getBarcodeTypeFromString('code128');
    final canRenderBarcode = barcodeData.trim().isNotEmpty;

    // Convert mm to approximate pixels (1mm ~= 3.78px at 96dpi)
    final width = (settings.labelWidthMm * 3.78 * scale).clamp(1.0, double.infinity);
    final height = (settings.labelHeightMm * 3.78 * scale).clamp(1.0, double.infinity);

    final padding = (8 * scale).clamp(1.0, height * 0.12);
    final contentHeight = (height - (padding * 2)).clamp(1.0, double.infinity);
    final densityFactor = contentHeight < 30
        ? 0.55
        : (contentHeight < 45 ? 0.7 : (contentHeight < 60 ? 0.85 : 1.0));

    final gapSmall = (2 * scale * densityFactor).clamp(0.0, double.infinity);

    final hasCompanyName = settings.includeCompanyName && companyProfile.name.isNotEmpty;
    final hasCompanyAddress =
        settings.includeCompanyContact && (companyProfile.address?.isNotEmpty ?? false);
    final hasCompanyPhone =
        settings.includeCompanyContact && (companyProfile.phone?.isNotEmpty ?? false);
    final hasProductName = settings.includeName && product.name.isNotEmpty;
    final hasVariantInfo = settings.includeVariantInfo;
    final hasSku = settings.includeSku && (product.sku?.trim().isNotEmpty ?? false);
    final hasPrice = settings.includePrice;

    final companyNameFont = 8 * scale * densityFactor;
    final companyContactFont = 6 * scale * densityFactor;
    final productNameFont = 10 * scale * densityFactor;
    final variantFont = 7 * scale * densityFactor;
    final skuFont = 7 * scale * densityFactor;
    final priceFont = 12 * scale * densityFactor;

    double lineHeight(double fontSize) => (fontSize * 1.35).clamp(1.0, double.infinity);

    var reserved = 0.0;
    if (hasCompanyName) {
      reserved += lineHeight(companyNameFont) + gapSmall;
    }
    if (hasCompanyAddress) {
      reserved += lineHeight(companyContactFont);
    }
    if (hasCompanyPhone) {
      reserved += lineHeight(companyContactFont);
    }
    if (hasCompanyAddress || hasCompanyPhone) {
      reserved += gapSmall;
    }
    if (hasProductName) {
      reserved += lineHeight(productNameFont) + gapSmall;
    }
    if (hasVariantInfo) {
      reserved += lineHeight(variantFont) + gapSmall;
    }
    if (hasSku) {
      reserved += gapSmall + lineHeight(skuFont);
    }
    if (hasPrice) {
      reserved += gapSmall + lineHeight(priceFont);
    }

    final maxBarcodeHeight = (contentHeight * 0.62).clamp(6.0, contentHeight);
    final barcodeAreaHeight = ((contentHeight - reserved) * 0.92).clamp(6.0, maxBarcodeHeight);

    return Card(
      elevation: 4,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.grey.shade300),
        ),
        padding: EdgeInsets.all(padding),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return ClipRect(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: SizedBox(
                  width: constraints.maxWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Company name (if enabled)
                      if (settings.includeCompanyName && companyProfile.name.isNotEmpty) ...[
                        Text(
                          companyProfile.name,
                          style: TextStyle(
                            fontSize: 8 * scale * densityFactor,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: gapSmall),
                      ],

              // Company contact (address + phone)
              if (settings.includeCompanyContact &&
                  ((companyProfile.address?.isNotEmpty ?? false) ||
                      (companyProfile.phone?.isNotEmpty ?? false))) ...[
                if (companyProfile.address?.isNotEmpty ?? false)
                  Text(
                    companyProfile.address!,
                    style: TextStyle(
                      fontSize: 6 * scale * densityFactor,
                      color: Colors.black54,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                if (companyProfile.phone?.isNotEmpty ?? false)
                  Text(
                    companyProfile.phone!,
                    style: TextStyle(
                      fontSize: 6 * scale * densityFactor,
                      color: Colors.black54,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                SizedBox(height: gapSmall),
              ],

              // Product name (if enabled)
              if (settings.includeName && product.name.isNotEmpty) ...[
                Text(
                  product.name,
                  style: TextStyle(
                    fontSize: 10 * scale * densityFactor,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: gapSmall),
              ],

              // Variant info (if enabled)
              if (settings.includeVariantInfo) ...[
                Text(
                  (variantInfo != null && variantInfo!.trim().isNotEmpty)
                      ? variantInfo!
                      : 'barcode.variant_placeholder'.tr(),
                  style: TextStyle(
                    fontSize: 7 * scale * densityFactor,
                    color: Colors.black54,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: gapSmall),
              ],

              // Barcode
              if (settings.includeBarcode)
                SizedBox(
                  height: barcodeAreaHeight,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final barcodeWidth = constraints.maxWidth.clamp(1.0, double.infinity);
                      final barcodeHeight = constraints.maxHeight.clamp(1.0, double.infinity);

                      if (barcodeWidth < 4 || barcodeHeight < 4) {
                        return Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        );
                      }

                      if (!canRenderBarcode) {
                        return Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'barcode.no_barcode'.tr(),
                            style: TextStyle(
                              fontSize: 8 * scale,
                              color: Colors.grey.shade600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        );
                      }

                      return BarcodeWidget(
                        barcode: barcodeType,
                        data: barcodeData,
                        width: barcodeWidth,
                        height: barcodeHeight,
                        drawText: true,
                        style: TextStyle(fontSize: 8 * scale * densityFactor),
                        errorBuilder: (context, error) {
                          return BarcodeWidget(
                            barcode: fallbackBarcodeType,
                            data: barcodeData,
                            width: barcodeWidth,
                            height: barcodeHeight,
                            drawText: true,
                            style: TextStyle(fontSize: 8 * scale * densityFactor),
                            errorBuilder: (context, error) {
                              return Container(
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'barcode.invalid_format'.tr(),
                                  style: TextStyle(
                                    fontSize: 8 * scale * densityFactor,
                                    color: Colors.grey.shade600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),

              // SKU (if enabled)
              if (settings.includeSku && (product.sku?.trim().isNotEmpty ?? false)) ...[
                SizedBox(height: gapSmall),
                Text(
                  'SKU: ${product.sku}',
                  style: TextStyle(
                    fontSize: 7 * scale * densityFactor,
                    color: Colors.black54,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],

                      // Price (if enabled)
                      if (settings.includePrice) ...[
                        SizedBox(height: gapSmall),
                        Text(
                          currencyService.format(product.priceCents.toBigInt().toInt()),
                          style: TextStyle(
                            fontSize: 12 * scale * densityFactor,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
