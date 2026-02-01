import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../products/domain/entities/product_entity.dart';
import '../../../settings/domain/entities/company_profile.dart';
import '../../domain/models/barcode_design_state.dart';
import 'barcode_preview_widget.dart';

/// A4 page preview showing multiple labels in grid layout
class A4PreviewWidget extends StatelessWidget {
  final Product product;
  final BarcodeDesignSettings settings;
  final CompanyProfile companyProfile;
  final String? variantInfo;
  final int copies;
  final double scale;

  const A4PreviewWidget({
    super.key,
    required this.product,
    required this.settings,
    required this.companyProfile,
    this.variantInfo,
    this.copies = 1,
    this.scale = 0.5,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // A4 dimensions in mm
    const a4WidthMm = 210.0;
    const a4HeightMm = 297.0;

    // Convert to pixels (1mm ~= 3.78px at 96dpi)
    final a4Width = a4WidthMm * 3.78 * scale;
    final a4Height = a4HeightMm * 3.78 * scale;

    final pagePaddingPx = settings.pageMarginMm * 3.78 * scale;
    final usableWidth = (a4Width - (pagePaddingPx * 2)).clamp(1.0, double.infinity);

    final labelScale = scale * 0.8;
    final labelWidthPx = settings.labelWidthMm * 3.78 * labelScale;
    final hGapPx = settings.horizontalGapMm * 3.78 * scale;
    final rowWidthPx = (settings.labelsPerRow * labelWidthPx) + ((settings.labelsPerRow - 1) * hGapPx);
    final isRowTooWide = rowWidthPx > usableWidth;

    // Calculate how many labels fit
    final labelsPerRow = settings.labelsPerRow;
    final labelsPerColumn = settings.calculatedLabelsPerColumn;
    final labelsPerPage = labelsPerRow * labelsPerColumn;
    final labelsToShow = copies.clamp(1, labelsPerPage);
    final rowsToShow = ((labelsToShow / labelsPerRow).ceil()).clamp(1, 6);

    return Card(
      elevation: 4,
      child: Container(
        width: a4Width,
        height: a4Height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.grey.shade400, width: 2),
        ),
        padding: EdgeInsets.all(pagePaddingPx),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header info
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(Icons.picture_as_pdf, size: 16 * scale, color: colorScheme.primary),
                  SizedBox(width: 4 * scale),
                  Text(
                    'barcode.a4_preview'.tr(),
                    style: TextStyle(
                      fontSize: 10 * scale,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '$labelsPerRow × $labelsPerColumn',
                    style: TextStyle(
                      fontSize: 8 * scale,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: Colors.grey.shade300),
            SizedBox(height: 4 * scale),
            if (isRowTooWide) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 14 * scale, color: colorScheme.onErrorContainer),
                    SizedBox(width: 6 * scale),
                    Expanded(
                      child: Text(
                        'barcode.preview_too_wide'.tr(),
                        style: TextStyle(
                          fontSize: 9 * scale,
                          color: colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 6 * scale),
            ],
            // Grid of labels
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: List.generate(
                    rowsToShow,
                    (rowIndex) {
                      final startIndex = rowIndex * labelsPerRow;
                      if (startIndex >= labelsToShow) {
                        return const SizedBox.shrink();
                      }
                      final labelsInRow = (startIndex + labelsPerRow) <= labelsToShow
                          ? labelsPerRow
                          : (labelsToShow - startIndex);

                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: settings.verticalGapMm * 3.78 * scale,
                        ),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: SizedBox(
                            width: double.infinity,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: List.generate(
                                  labelsInRow,
                                  (colIndex) => Padding(
                                    padding: EdgeInsets.only(
                                      right: colIndex < labelsInRow - 1
                                          ? settings.horizontalGapMm * 3.78 * scale
                                          : 0,
                                    ),
                                    child: BarcodePreviewWidget(
                                      product: product,
                                      settings: settings,
                                      companyProfile: companyProfile,
                                      variantInfo: variantInfo,
                                      scale: labelScale, // Smaller for grid
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            if (labelsPerColumn > 6) ...[
              SizedBox(height: 4 * scale),
              Center(
                child: Text(
                  'barcode.more_rows'.tr(args: [(labelsPerColumn - 6).toString()]),
                  style: TextStyle(
                    fontSize: 8 * scale,
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class A4BatchPreviewWidget extends StatelessWidget {
  final List<({Product product, String? variantInfo})> labels;
  final BarcodeDesignSettings settings;
  final CompanyProfile companyProfile;
  final double scale;

  const A4BatchPreviewWidget({
    super.key,
    required this.labels,
    required this.settings,
    required this.companyProfile,
    this.scale = 0.5,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // A4 dimensions in mm
    const a4WidthMm = 210.0;
    const a4HeightMm = 297.0;

    // Convert to pixels (1mm ~= 3.78px at 96dpi)
    final a4Width = a4WidthMm * 3.78 * scale;
    final a4Height = a4HeightMm * 3.78 * scale;

    final pagePaddingPx = settings.pageMarginMm * 3.78 * scale;
    final usableWidth = (a4Width - (pagePaddingPx * 2)).clamp(1.0, double.infinity);

    final labelScale = scale * 0.8;
    final labelWidthPx = settings.labelWidthMm * 3.78 * labelScale;
    final hGapPx = settings.horizontalGapMm * 3.78 * scale;
    final rowWidthPx = (settings.labelsPerRow * labelWidthPx) + ((settings.labelsPerRow - 1) * hGapPx);
    final isRowTooWide = rowWidthPx > usableWidth;

    final labelsPerRow = settings.labelsPerRow;
    final labelsPerColumn = settings.calculatedLabelsPerColumn;
    final labelsPerPage = labelsPerRow * labelsPerColumn;

    final labelsToShow = labels.take(labelsPerPage).toList(growable: false);
    final rowsToShow = ((labelsToShow.length / labelsPerRow).ceil()).clamp(1, 6);

    return Card(
      elevation: 4,
      child: Container(
        width: a4Width,
        height: a4Height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.grey.shade400, width: 2),
        ),
        padding: EdgeInsets.all(pagePaddingPx),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(Icons.picture_as_pdf, size: 16 * scale, color: colorScheme.primary),
                  SizedBox(width: 4 * scale),
                  Text(
                    'barcode.a4_preview'.tr(),
                    style: TextStyle(
                      fontSize: 10 * scale,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '$labelsPerRow × $labelsPerColumn',
                    style: TextStyle(
                      fontSize: 8 * scale,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: Colors.grey.shade300),
            SizedBox(height: 4 * scale),
            if (isRowTooWide) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 14 * scale, color: colorScheme.onErrorContainer),
                    SizedBox(width: 6 * scale),
                    Expanded(
                      child: Text(
                        'barcode.preview_too_wide'.tr(),
                        style: TextStyle(
                          fontSize: 9 * scale,
                          color: colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 6 * scale),
            ],
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: List.generate(
                    rowsToShow,
                    (rowIndex) {
                      final startIndex = rowIndex * labelsPerRow;
                      if (startIndex >= labelsToShow.length) {
                        return const SizedBox.shrink();
                      }
                      final labelsInRow = (startIndex + labelsPerRow) <= labelsToShow.length
                          ? labelsPerRow
                          : (labelsToShow.length - startIndex);

                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: settings.verticalGapMm * 3.78 * scale,
                        ),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: SizedBox(
                            width: double.infinity,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: List.generate(
                                  labelsInRow,
                                  (colIndex) {
                                    final label = labelsToShow[startIndex + colIndex];
                                    return Padding(
                                      padding: EdgeInsets.only(
                                        right: colIndex < labelsInRow - 1
                                            ? settings.horizontalGapMm * 3.78 * scale
                                            : 0,
                                      ),
                                      child: BarcodePreviewWidget(
                                        product: label.product,
                                        settings: settings,
                                        companyProfile: companyProfile,
                                        variantInfo: label.variantInfo,
                                        scale: labelScale,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            if (labelsPerColumn > 6) ...[
              SizedBox(height: 4 * scale),
              Center(
                child: Text(
                  'barcode.more_rows'.tr(args: [(labelsPerColumn - 6).toString()]),
                  style: TextStyle(
                    fontSize: 8 * scale,
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
