import 'dart:convert';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/measurement/measurement_localization.dart';
import '../../../../core/services/currency_service.dart';
import '../../../settings/data/services/company_profile_service.dart';
import '../../../settings/domain/entities/company_profile.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/presentation/bloc/app_settings_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/daos/adjustment_return_dao.dart'
    show PurchaseAdjReturnItemWithDetails;
import '../../domain/entities/purchase_entity.dart';
import '../../../suppliers/domain/repositories/supplier_repository.dart';
import '../bloc/purchase_form_bloc.dart';
import '../bloc/purchase_adj_return_form_bloc.dart'
    show parseAdjReturnNotes, adjReturnReasonLabel;

class PurchasePdfService {
  /// Generate and print a purchase invoice PDF from saved purchase data
  static Future<void> printPurchaseInvoice({
    required BuildContext context,
    required PurchaseEntity purchase,
    required List<PurchaseItemEntity> items,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();
    final appSettings = sl<AppSettingsBloc>().state.settings;

    final pdf = await _buildPurchaseInvoicePdf(
      purchase: purchase,
      items: items,
      cs: cs,
      locale: locale,
      isRtl: isRtl,
      company: company,
      appSettings: appSettings,
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Purchase_${purchase.purchaseNumber}',
    );
  }

  /// Generate and share a purchase invoice PDF from saved purchase data
  static Future<void> sharePurchaseInvoice({
    required BuildContext context,
    required PurchaseEntity purchase,
    required List<PurchaseItemEntity> items,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();
    final appSettings = sl<AppSettingsBloc>().state.settings;

    final pdf = await _buildPurchaseInvoicePdf(
      purchase: purchase,
      items: items,
      cs: cs,
      locale: locale,
      isRtl: isRtl,
      company: company,
      appSettings: appSettings,
    );

    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'Purchase_${purchase.purchaseNumber}.pdf',
    );
  }

  /// Generate and print a purchase invoice PDF from current form state
  static Future<void> printFromFormState({
    required BuildContext context,
    required PurchaseFormState state,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();
    final appSettings = sl<AppSettingsBloc>().state.settings;

    final pdf = await _buildPurchaseInvoiceFromState(
      state: state,
      cs: cs,
      locale: locale,
      isRtl: isRtl,
      company: company,
      appSettings: appSettings,
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Purchase_${state.purchaseNumber ?? state.purchaseId ?? 'draft'}',
    );
  }

  /// Generate and share a purchase invoice PDF from current form state
  static Future<void> shareFromFormState({
    required BuildContext context,
    required PurchaseFormState state,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();
    final appSettings = sl<AppSettingsBloc>().state.settings;

    final pdf = await _buildPurchaseInvoiceFromState(
      state: state,
      cs: cs,
      locale: locale,
      isRtl: isRtl,
      company: company,
      appSettings: appSettings,
    );

    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'Purchase_${state.purchaseNumber ?? state.purchaseId ?? 'draft'}.pdf',
    );
  }

  /// Generate and print a purchase return invoice PDF
  static Future<void> printPurchaseReturn({
    required BuildContext context,
    required PurchaseEntity originalPurchase,
    required PurchaseReturnEntity returnEntity,
    required List<PurchaseReturnItemEntity> returnItems,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();
    final appSettings = sl<AppSettingsBloc>().state.settings;

    final pdf = await _buildPurchaseReturnPdf(
      originalPurchase: originalPurchase,
      returnEntity: returnEntity,
      returnItems: returnItems,
      cs: cs,
      locale: locale,
      isRtl: isRtl,
      company: company,
      appSettings: appSettings,
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'PurchaseReturn_${returnEntity.id}',
    );
  }

  /// Generate and share a purchase return invoice PDF
  static Future<void> sharePurchaseReturn({
    required BuildContext context,
    required PurchaseEntity originalPurchase,
    required PurchaseReturnEntity returnEntity,
    required List<PurchaseReturnItemEntity> returnItems,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();
    final appSettings = sl<AppSettingsBloc>().state.settings;

    final pdf = await _buildPurchaseReturnPdf(
      originalPurchase: originalPurchase,
      returnEntity: returnEntity,
      returnItems: returnItems,
      cs: cs,
      locale: locale,
      isRtl: isRtl,
      company: company,
      appSettings: appSettings,
    );

    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'PurchaseReturn_${returnEntity.returnNumber}.pdf',
    );
  }

  // ═══════════════════════════════════════════════════════
  // PURCHASE INVOICE PDF FROM ENTITY
  // ═══════════════════════════════════════════════════════
  static Future<pw.Document> _buildPurchaseInvoicePdf({
    required PurchaseEntity purchase,
    required List<PurchaseItemEntity> items,
    required CurrencyService cs,
    required Locale locale,
    required bool isRtl,
    required CompanyProfile company,
    required AppSettings appSettings,
  }) async {
    final fonts = await _loadFonts();
    final pdf = pw.Document();

    // Fetch supplier balance for the PDF footer
    pw.Widget? supplierBalanceWidget;
    try {
      final supplierRepo = sl<SupplierRepository>();
      final supplier = await supplierRepo.getSupplier(purchase.supplierId);
      if (supplier != null) {
        supplierBalanceWidget = _buildSupplierBalance(
          supplierName: supplier.name,
          balanceCents: supplier.balanceCents.toBigInt().toInt(),
          cs: cs,
          fonts: fonts,
        );
      }
    } catch (_) {}

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        textDirection: isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _buildHeader(
                company: company,
                title: 'purchases.title'.tr(),
                fonts: fonts,
                isRtl: isRtl,
                receiptHeaderText: appSettings.showHeaderFooterOnPurchases
                    ? appSettings.receiptHeaderText
                    : null,
                taxRegistrationNumber: appSettings.taxRegistrationNumber,
              ),
              pw.SizedBox(height: 16),
              _buildInvoiceInfo(
                invoiceNumber: purchase.purchaseNumber.isNotEmpty
                    ? purchase.purchaseNumber
                    : '${purchase.id}',
                date: purchase.purchaseDate,
                supplierName: purchase.supplierName,
                paymentMethod: purchase.paymentMethod,
                locale: locale,
                fonts: fonts,
              ),
              pw.SizedBox(height: 16),
              _buildItemsTable(
                items: items
                    .map(
                      (item) => _PdfLineItem(
                        name: item.productName ?? 'Product #${item.productId}',
                        variantSku: item.variantSku,
                        quantity: item.quantity,
                        measurementType: item.measurementType,
                        unitCostCents: item.unitCostCents.toBigInt().toInt(),
                        totalCents: item.totalCents.toBigInt().toInt(),
                      ),
                    )
                    .toList(),
                cs: cs,
                fonts: fonts,
                isRtl: isRtl,
              ),
              pw.SizedBox(height: 16),
              _buildTotals(
                subtotalCents: purchase.subtotalCents.toBigInt().toInt(),
                discountCents: purchase.discountCents.toBigInt().toInt(),
                taxCents: purchase.taxCents.toBigInt().toInt(),
                totalCents: purchase.totalCents.toBigInt().toInt(),
                totalItems: items.length,
                quantitySummary: localizedQuantitySummary(
                  items,
                  quantityOf: (item) => item.quantity,
                  measurementTypeOf: (item) => item.measurementType,
                ),
                cs: cs,
                fonts: fonts,
                includeTaxBreakdown: appSettings.includeTaxBreakdown,
              ),
              if (purchase.notes != null && purchase.notes!.isNotEmpty) ...[
                pw.SizedBox(height: 12),
                pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _bidiText(
                        'purchases.notes'.tr(),
                        fonts.bold,
                        fontSize: 10,
                      ),
                      pw.SizedBox(height: 4),
                      _bidiText(purchase.notes!, fonts.regular, fontSize: 9),
                    ],
                  ),
                ),
              ],
              if (supplierBalanceWidget != null) ...[
                pw.SizedBox(height: 12),
                supplierBalanceWidget,
              ],
              pw.SizedBox(height: 20),
              _buildFooter(
                fonts: fonts,
                locale: locale,
                receiptFooterText: appSettings.showHeaderFooterOnPurchases
                    ? appSettings.receiptFooterText
                    : null,
              ),
            ],
          );
        },
      ),
    );

    return pdf;
  }

  // ═══════════════════════════════════════════════════════
  // PURCHASE INVOICE PDF FROM FORM STATE
  // ═══════════════════════════════════════════════════════
  static Future<pw.Document> _buildPurchaseInvoiceFromState({
    required PurchaseFormState state,
    required CurrencyService cs,
    required Locale locale,
    required bool isRtl,
    required CompanyProfile company,
    required AppSettings appSettings,
  }) async {
    final fonts = await _loadFonts();
    final pdf = pw.Document();

    // Fetch supplier balance for the PDF footer (best-effort)
    pw.Widget? supplierBalanceWidget;
    try {
      if (state.supplierId != null) {
        final supplierRepo = sl<SupplierRepository>();
        final supplier = await supplierRepo.getSupplier(state.supplierId!);
        if (supplier != null) {
          supplierBalanceWidget = _buildSupplierBalance(
            supplierName: supplier.name,
            balanceCents: supplier.balanceCents.toBigInt().toInt(),
            cs: cs,
            fonts: fonts,
          );
        }
      }
    } catch (_) {}

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        textDirection: isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _buildHeader(
                company: company,
                title: 'purchases.title'.tr(),
                fonts: fonts,
                isRtl: isRtl,
                receiptHeaderText: appSettings.showHeaderFooterOnPurchases
                    ? appSettings.receiptHeaderText
                    : null,
                taxRegistrationNumber: appSettings.taxRegistrationNumber,
                showLogo: appSettings.showLogoOnReceipt,
              ),
              pw.SizedBox(height: 16),
              _buildInvoiceInfo(
                invoiceNumber:
                    state.purchaseNumber ?? '${state.purchaseId ?? ''}',
                date: state.purchaseDate,
                supplierName: state.supplierName,
                paymentMethod: state.paymentMethod.name,
                locale: locale,
                fonts: fonts,
              ),
              pw.SizedBox(height: 16),
              _buildItemsTable(
                items: state.items
                    .map(
                      (item) => _PdfLineItem(
                        name: item.product.name,
                        variantSku: item.variant?.sku,
                        quantity: item.quantity,
                        measurementType: item.product.measurementType,
                        unitCostCents: item.unitCostCents.toBigInt().toInt(),
                        totalCents: item.totalCents.toBigInt().toInt(),
                      ),
                    )
                    .toList(),
                cs: cs,
                fonts: fonts,
                isRtl: isRtl,
              ),
              pw.SizedBox(height: 16),
              _buildTotals(
                subtotalCents: state.subtotalCents.toBigInt().toInt(),
                discountCents: state.totalDiscountCents.toBigInt().toInt(),
                taxCents: state.taxCents.toBigInt().toInt(),
                totalCents: state.totalCents.toBigInt().toInt(),
                totalItems: state.items.length,
                quantitySummary: localizedQuantitySummary(
                  state.items,
                  quantityOf: (item) => item.quantity,
                  measurementTypeOf: (item) => item.product.measurementType,
                ),
                cs: cs,
                fonts: fonts,
                includeTaxBreakdown: appSettings.includeTaxBreakdown,
              ),
              if (state.notes != null && state.notes!.isNotEmpty) ...[
                pw.SizedBox(height: 12),
                pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _bidiText(
                        'purchases.notes'.tr(),
                        fonts.bold,
                        fontSize: 10,
                      ),
                      pw.SizedBox(height: 4),
                      _bidiText(state.notes!, fonts.regular, fontSize: 9),
                    ],
                  ),
                ),
              ],
              if (supplierBalanceWidget != null) ...[
                pw.SizedBox(height: 12),
                supplierBalanceWidget,
              ],
              pw.SizedBox(height: 20),
              _buildFooter(
                fonts: fonts,
                locale: locale,
                receiptFooterText: appSettings.showHeaderFooterOnPurchases
                    ? appSettings.receiptFooterText
                    : null,
              ),
            ],
          );
        },
      ),
    );

    return pdf;
  }

  // ═══════════════════════════════════════════════════════
  // PURCHASE RETURN PDF
  // ═══════════════════════════════════════════════════════
  static Future<pw.Document> _buildPurchaseReturnPdf({
    required PurchaseEntity originalPurchase,
    required PurchaseReturnEntity returnEntity,
    required List<PurchaseReturnItemEntity> returnItems,
    required CurrencyService cs,
    required Locale locale,
    required bool isRtl,
    required CompanyProfile company,
    required AppSettings appSettings,
  }) async {
    final fonts = await _loadFonts();
    final pdf = pw.Document();

    // Fetch supplier balance for the PDF footer
    pw.Widget? supplierBalanceWidget;
    try {
      final supplierRepo = sl<SupplierRepository>();
      final supplier = await supplierRepo.getSupplier(
        originalPurchase.supplierId,
      );
      if (supplier != null) {
        supplierBalanceWidget = _buildSupplierBalance(
          supplierName: supplier.name,
          balanceCents: supplier.balanceCents.toBigInt().toInt(),
          cs: cs,
          fonts: fonts,
        );
      }
    } catch (_) {}

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        textDirection: isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _buildHeader(
                company: company,
                title: 'purchases.purchase_return'.tr(),
                fonts: fonts,
                isRtl: isRtl,
                showLogo: appSettings.showLogoOnReceipt,
              ),
              pw.SizedBox(height: 16),
              // Return info
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _pdfInfoRow(
                      'purchases.return_number'.tr(),
                      returnEntity.returnNumber,
                      fonts.regular,
                    ),
                    _pdfInfoRow(
                      'purchases.return_date'.tr(),
                      DateFormat('dd/MM/yyyy').format(returnEntity.returnDate),
                      fonts.regular,
                    ),
                    _pdfInfoRow(
                      'purchases.return_from_purchase'.tr(),
                      originalPurchase.purchaseNumber.isNotEmpty
                          ? originalPurchase.purchaseNumber
                          : '${originalPurchase.id}',
                      fonts.regular,
                    ),
                    if (originalPurchase.supplierName != null)
                      _pdfInfoRow(
                        'purchases.supplier'.tr(),
                        originalPurchase.supplierName!,
                        fonts.regular,
                      ),
                    _pdfInfoRow(
                      'purchases.refund_method'.tr(),
                      'purchases.refund_method_${returnEntity.refundMethod}'
                          .tr(),
                      fonts.regular,
                    ),
                    _pdfInfoRow(
                      'purchases.disposition_type'.tr(),
                      'purchases.disposition_${returnEntity.dispositionType}'
                          .tr(),
                      fonts.regular,
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),
              // Return items table
              _buildReturnItemsTable(
                items: returnItems,
                cs: cs,
                fonts: fonts,
                isRtl: isRtl,
              ),
              pw.SizedBox(height: 16),
              // Return summary (items + pieces + total)
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.red50,
                  border: pw.Border.all(color: PdfColors.red200),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Column(
                  children: [
                    _pdfMoneyRow(
                      'purchases.total_items_count'.tr(),
                      '${returnItems.length}',
                      fonts.regular,
                    ),
                    _pdfMoneyRow(
                      'measurement.total_quantity'.tr(),
                      localizedQuantitySummary(
                        returnItems,
                        quantityOf: (item) => item.quantity,
                        measurementTypeOf: (item) => item.measurementType,
                      ),
                      fonts.regular,
                    ),
                    pw.SizedBox(height: 4),
                    _pdfMoneyRow(
                      'purchases.subtotal'.tr(),
                      cs.format(returnEntity.subtotalCents.toBigInt().toInt()),
                      fonts.regular,
                    ),
                    if (returnEntity.discountCents.toBigInt().toInt() > 0)
                      _pdfMoneyRow(
                        'purchases.discount'.tr(),
                        '- ${cs.format(returnEntity.discountCents.toBigInt().toInt())}',
                        fonts.regular,
                        valueColor: PdfColors.orange,
                      ),
                    if (returnEntity.taxCents.toBigInt().toInt() > 0)
                      _pdfMoneyRow(
                        'purchases.tax'.tr(),
                        '+ ${cs.format(returnEntity.taxCents.toBigInt().toInt())}',
                        fonts.regular,
                      ),
                    pw.Divider(thickness: 2),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        _bidiText(
                          'purchases.return_total'.tr(),
                          fonts.bold,
                          fontSize: 14,
                        ),
                        pw.Text(
                          cs.format(returnEntity.totalCents.toBigInt().toInt()),
                          style: pw.TextStyle(
                            font: fonts.bold,
                            fontSize: 14,
                            color: PdfColors.red,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (returnEntity.reason != null &&
                  returnEntity.reason!.isNotEmpty) ...[
                pw.SizedBox(height: 12),
                pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _bidiText(
                        'purchases.return_reason'.tr(),
                        fonts.bold,
                        fontSize: 10,
                      ),
                      pw.SizedBox(height: 4),
                      _bidiText(
                        returnEntity.reason!,
                        fonts.regular,
                        fontSize: 9,
                      ),
                    ],
                  ),
                ),
              ],
              if (supplierBalanceWidget != null) ...[
                pw.SizedBox(height: 12),
                supplierBalanceWidget,
              ],
              pw.SizedBox(height: 20),
              _buildFooter(fonts: fonts, locale: locale),
            ],
          );
        },
      ),
    );

    return pdf;
  }

  // ═══════════════════════════════════════════════════════
  // SHARED PDF BUILDING BLOCKS
  // ═══════════════════════════════════════════════════════

  static Future<_PdfFonts> _loadFonts() async {
    final fontData = await rootBundle.load(
      'assets/fonts/IBMPlexSansArabic-Regular.ttf',
    );
    final fontBoldData = await rootBundle.load(
      'assets/fonts/IBMPlexSansArabic-Bold.ttf',
    );
    return _PdfFonts(
      regular: pw.Font.ttf(fontData),
      bold: pw.Font.ttf(fontBoldData),
    );
  }

  static pw.Widget _buildHeader({
    required CompanyProfile company,
    required String title,
    required _PdfFonts fonts,
    required bool isRtl,
    String? receiptHeaderText,
    String? taxRegistrationNumber,
    bool showLogo = true,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue50,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (showLogo &&
                      company.logoBase64 != null &&
                      company.logoBase64!.isNotEmpty)
                    pw.Container(
                      width: 40,
                      height: 40,
                      margin: const pw.EdgeInsets.only(bottom: 8),
                      decoration: const pw.BoxDecoration(
                        shape: pw.BoxShape.circle,
                      ),
                      child: pw.ClipOval(
                        child: pw.Image(
                          pw.MemoryImage(base64Decode(company.logoBase64!)),
                          fit: pw.BoxFit.cover,
                        ),
                      ),
                    ),
                  if (company.name.isNotEmpty)
                    _bidiText(company.name, fonts.bold, fontSize: 16),
                  if (company.address != null && company.address!.isNotEmpty)
                    _bidiText(
                      company.address!,
                      fonts.regular,
                      fontSize: 8,
                      color: PdfColors.grey600,
                    ),
                  if (company.phone != null && company.phone!.isNotEmpty)
                    _bidiText(
                      company.phone!,
                      fonts.regular,
                      fontSize: 8,
                      color: PdfColors.grey600,
                    ),
                  if ((taxRegistrationNumber != null &&
                          taxRegistrationNumber.isNotEmpty) ||
                      (company.taxNumber != null &&
                          company.taxNumber!.isNotEmpty))
                    _bidiText(
                      'Tax: ${taxRegistrationNumber ?? company.taxNumber}',
                      fonts.regular,
                      fontSize: 8,
                      color: PdfColors.grey600,
                    ),
                ],
              ),
              _bidiText(
                title,
                fonts.bold,
                fontSize: 20,
                color: PdfColors.blue800,
              ),
            ],
          ),
          if (receiptHeaderText != null && receiptHeaderText.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            _bidiText(
              receiptHeaderText,
              fonts.regular,
              fontSize: 9,
              color: PdfColors.grey700,
            ),
          ],
        ],
      ),
    );
  }

  static String _translatePaymentMethod(String method) {
    switch (method) {
      case 'cash':
        return 'purchases.payment_cash'.tr();
      case 'credit':
        return 'purchases.payment_credit'.tr();
      case 'card':
        return 'purchases.payment_card'.tr();
      case 'cheque':
        return 'purchases.payment_cheque'.tr();
      case 'mixed':
        return 'purchases.payment_mixed'.tr();
      case 'purchaseOrder':
        return 'purchases.payment_po'.tr();
      default:
        return method;
    }
  }

  static pw.Widget _buildInvoiceInfo({
    required String invoiceNumber,
    required DateTime date,
    required String? supplierName,
    String? paymentMethod,
    required Locale locale,
    required _PdfFonts fonts,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _pdfInfoRow(
            'purchases.invoice_number'.tr(),
            invoiceNumber,
            fonts.regular,
          ),
          _pdfInfoRow(
            'purchases.invoice_date'.tr(),
            DateFormat('dd/MM/yyyy').format(date),
            fonts.regular,
          ),
          if (supplierName != null)
            _pdfInfoRow('purchases.supplier'.tr(), supplierName, fonts.regular),
          if (paymentMethod != null && paymentMethod.isNotEmpty)
            _pdfInfoRow(
              'purchases.payment_method'.tr(),
              _translatePaymentMethod(paymentMethod),
              fonts.regular,
            ),
        ],
      ),
    );
  }

  static pw.Widget _buildItemsTable({
    required List<_PdfLineItem> items,
    required CurrencyService cs,
    required _PdfFonts fonts,
    required bool isRtl,
  }) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      columnWidths: {
        0: const pw.FlexColumnWidth(1),
        1: const pw.FlexColumnWidth(3),
        2: const pw.FlexColumnWidth(1),
        3: const pw.FlexColumnWidth(1.5),
        4: const pw.FlexColumnWidth(1.5),
      },
      children: [
        // Header
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _tableCell('#', fonts.bold, isHeader: true),
            _tableCell('purchases.product'.tr(), fonts.bold, isHeader: true),
            _tableCell('purchases.qty'.tr(), fonts.bold, isHeader: true),
            _tableCell('purchases.unit_cost'.tr(), fonts.bold, isHeader: true),
            _tableCell('purchases.total'.tr(), fonts.bold, isHeader: true),
          ],
        ),
        // Items
        ...items.asMap().entries.map((entry) {
          final idx = entry.key;
          final item = entry.value;
          final displayName = item.variantSku != null
              ? '${item.name} (${item.variantSku})'
              : item.name;
          return pw.TableRow(
            children: [
              _tableCell('${idx + 1}', fonts.regular),
              _tableCell(displayName, fonts.regular),
              _tableCell(
                localizedQuantity(item.quantity, item.measurementType),
                fonts.regular,
              ),
              _tableCell(cs.format(item.unitCostCents), fonts.regular),
              _tableCell(cs.format(item.totalCents), fonts.regular),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _buildReturnItemsTable({
    required List<PurchaseReturnItemEntity> items,
    required CurrencyService cs,
    required _PdfFonts fonts,
    required bool isRtl,
  }) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      columnWidths: {
        0: const pw.FlexColumnWidth(0.6),
        1: const pw.FlexColumnWidth(3),
        2: const pw.FlexColumnWidth(0.8),
        3: const pw.FlexColumnWidth(1.2),
        4: const pw.FlexColumnWidth(1.2),
        5: const pw.FlexColumnWidth(1.2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.red50),
          children: [
            _tableCell('#', fonts.bold, isHeader: true),
            _tableCell('purchases.product'.tr(), fonts.bold, isHeader: true),
            _tableCell('purchases.qty'.tr(), fonts.bold, isHeader: true),
            _tableCell('purchases.discount'.tr(), fonts.bold, isHeader: true),
            _tableCell('purchases.tax'.tr(), fonts.bold, isHeader: true),
            _tableCell('purchases.refund'.tr(), fonts.bold, isHeader: true),
          ],
        ),
        ...items.asMap().entries.map((entry) {
          final idx = entry.key;
          final item = entry.value;
          final productName =
              item.productName ?? 'Item #${item.purchaseItemId}';
          final variantParts = <String>[];
          if (item.colorName != null && item.colorName!.isNotEmpty) {
            variantParts.add(item.colorName!);
          }
          if (item.sizeName != null && item.sizeName!.isNotEmpty) {
            variantParts.add(item.sizeName!);
          }
          if (item.variantSku != null && item.variantSku!.isNotEmpty) {
            variantParts.add(item.variantSku!);
          }
          final variantLine = variantParts.isNotEmpty
              ? variantParts.join(' · ')
              : null;

          return pw.TableRow(
            children: [
              _tableCell('${idx + 1}', fonts.regular),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 4,
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _bidiText(productName, fonts.regular, fontSize: 8),
                    if (variantLine != null)
                      _bidiText(
                        variantLine,
                        fonts.regular,
                        fontSize: 7,
                        color: PdfColors.grey600,
                      ),
                  ],
                ),
              ),
              _tableCell(
                localizedQuantity(item.quantity, item.measurementType),
                fonts.regular,
              ),
              _tableCell(
                item.discountCents.toBigInt().toInt() > 0
                    ? cs.format(item.discountCents.toBigInt().toInt())
                    : '-',
                fonts.regular,
              ),
              _tableCell(
                item.taxCents.toBigInt().toInt() > 0
                    ? cs.format(item.taxCents.toBigInt().toInt())
                    : '-',
                fonts.regular,
              ),
              _tableCell(
                cs.format(item.refundCents.toBigInt().toInt()),
                fonts.regular,
              ),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _buildTotals({
    required int subtotalCents,
    required int discountCents,
    required int taxCents,
    required int totalCents,
    required int totalItems,
    required String quantitySummary,
    required CurrencyService cs,
    required _PdfFonts fonts,
    bool includeTaxBreakdown = true,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue50,
        border: pw.Border.all(color: PdfColors.blue200),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        children: [
          _pdfMoneyRow(
            'purchases.total_items_count'.tr(),
            '$totalItems',
            fonts.regular,
          ),
          _pdfMoneyRow(
            'measurement.total_quantity'.tr(),
            quantitySummary,
            fonts.regular,
          ),
          pw.SizedBox(height: 4),
          _pdfMoneyRow(
            'purchases.subtotal'.tr(),
            cs.format(subtotalCents),
            fonts.regular,
          ),
          if (discountCents > 0)
            _pdfMoneyRow(
              'purchases.discount'.tr(),
              '- ${cs.format(discountCents)}',
              fonts.regular,
              valueColor: PdfColors.orange,
            ),
          if (taxCents > 0 && includeTaxBreakdown)
            _pdfMoneyRow(
              'purchases.tax'.tr(),
              cs.format(taxCents),
              fonts.regular,
            ),
          pw.Divider(thickness: 2),
          _pdfMoneyRow(
            'purchases.total'.tr(),
            cs.format(totalCents),
            fonts.bold,
            fontSize: 14,
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSupplierBalance({
    required String supplierName,
    required int balanceCents,
    required CurrencyService cs,
    required _PdfFonts fonts,
  }) {
    final isCredit = balanceCents < 0; // negative = supplier owes you
    final absBalance = balanceCents.abs();
    final balanceLabel = isCredit
        ? 'purchases.balance_credit'.tr()
        : 'purchases.balance_you_owe'.tr();
    final balanceColor = isCredit ? PdfColors.green700 : PdfColors.red700;

    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _bidiText(
                'purchases.supplier_account'.tr(),
                fonts.bold,
                fontSize: 9,
              ),
              _bidiText(
                supplierName,
                fonts.regular,
                fontSize: 8,
                color: PdfColors.grey600,
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              _bidiText(
                balanceLabel,
                fonts.regular,
                fontSize: 8,
                color: PdfColors.grey600,
              ),
              pw.Text(
                cs.format(absBalance),
                style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: 11,
                  color: balanceColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildFooter({
    required _PdfFonts fonts,
    required Locale locale,
    String? receiptFooterText,
  }) {
    final generatedText =
        '${'purchases.generated_on'.tr()}: ${DateFormat('yyyy-MM-dd HH:mm', locale.toString()).format(DateTime.now())}';
    return pw.Column(
      children: [
        if (receiptFooterText != null && receiptFooterText.isNotEmpty) ...[
          _bidiText(
            receiptFooterText,
            fonts.regular,
            fontSize: 9,
            color: PdfColors.grey700,
          ),
          pw.SizedBox(height: 4),
        ],
        pw.Container(
          alignment: pw.Alignment.center,
          child: _bidiText(
            generatedText,
            fonts.regular,
            fontSize: 8,
            color: PdfColors.grey500,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Container(
          alignment: pw.Alignment.center,
          child: pw.Text(
            'Powered by TapixSolutions',
            style: pw.TextStyle(
              font: fonts.regular,
              fontSize: 7,
              color: PdfColors.grey400,
            ),
          ),
        ),
      ],
    );
  }

  /// Detect if text contains Arabic/Hebrew characters that need RTL
  static bool _hasArabic(String text) {
    return RegExp(
      r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF\u0590-\u05FF]',
    ).hasMatch(text);
  }

  /// Create a pw.Text that auto-detects Arabic and sets textDirection accordingly
  static pw.Text _bidiText(
    String text,
    pw.Font font, {
    double fontSize = 8,
    PdfColor? color,
  }) {
    return pw.Text(
      text,
      textDirection: _hasArabic(text)
          ? pw.TextDirection.rtl
          : pw.TextDirection.ltr,
      style: pw.TextStyle(font: font, fontSize: fontSize, color: color),
    );
  }

  static pw.Widget _tableCell(
    String text,
    pw.Font font, {
    bool isHeader = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: _bidiText(text, font, fontSize: 7),
    );
  }

  static pw.Widget _pdfInfoRow(String label, String value, pw.Font font) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          _bidiText(label, font, fontSize: 9, color: PdfColors.grey600),
          _bidiText(value, font, fontSize: 10),
        ],
      ),
    );
  }

  static pw.Widget _pdfMoneyRow(
    String label,
    String value,
    pw.Font font, {
    PdfColor? valueColor,
    double fontSize = 10,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          _bidiText(label, font, fontSize: fontSize),
          pw.Text(
            value,
            style: pw.TextStyle(
              font: font,
              fontSize: fontSize,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // PURCHASE ADJUSTMENT RETURN PDF (not linked to a purchase)
  // ═══════════════════════════════════════════════════════

  /// Generate and print a purchase adjustment return PDF.
  static Future<void> printPurchaseAdjReturn({
    required BuildContext context,
    required PurchaseReturnAdjustment returnEntity,
    required List<PurchaseAdjReturnItemWithDetails> returnItems,
    required String? supplierName,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();
    final appSettings = sl<AppSettingsBloc>().state.settings;

    final pdf = await _buildPurchaseAdjReturnPdf(
      returnEntity: returnEntity,
      returnItems: returnItems,
      supplierName: supplierName,
      cs: cs,
      locale: locale,
      isRtl: isRtl,
      company: company,
      appSettings: appSettings,
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'PurchaseAdjReturn_${returnEntity.returnNumber}',
    );
  }

  /// Generate and share a purchase adjustment return PDF.
  static Future<void> sharePurchaseAdjReturn({
    required BuildContext context,
    required PurchaseReturnAdjustment returnEntity,
    required List<PurchaseAdjReturnItemWithDetails> returnItems,
    required String? supplierName,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();
    final appSettings = sl<AppSettingsBloc>().state.settings;

    final pdf = await _buildPurchaseAdjReturnPdf(
      returnEntity: returnEntity,
      returnItems: returnItems,
      supplierName: supplierName,
      cs: cs,
      locale: locale,
      isRtl: isRtl,
      company: company,
      appSettings: appSettings,
    );

    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'PurchaseAdjReturn_${returnEntity.returnNumber}.pdf',
    );
  }

  static Future<pw.Document> _buildPurchaseAdjReturnPdf({
    required PurchaseReturnAdjustment returnEntity,
    required List<PurchaseAdjReturnItemWithDetails> returnItems,
    required String? supplierName,
    required CurrencyService cs,
    required Locale locale,
    required bool isRtl,
    required CompanyProfile company,
    required AppSettings appSettings,
  }) async {
    final fonts = await _loadFonts();
    final pdf = pw.Document();

    // Supplier balance for the PDF footer (best-effort).
    pw.Widget? supplierBalanceWidget;
    try {
      final supplierRepo = sl<SupplierRepository>();
      final supplier = await supplierRepo.getSupplier(returnEntity.supplierId);
      if (supplier != null) {
        supplierBalanceWidget = _buildSupplierBalance(
          supplierName: supplier.name,
          balanceCents: supplier.balanceCents.toBigInt().toInt(),
          cs: cs,
          fonts: fonts,
        );
      }
    } catch (_) {}

    final parsed = parseAdjReturnNotes(returnEntity.notes);
    final reasonText = parsed.reasonCode != null
        ? adjReturnReasonLabel(parsed.reasonCode)
        : null;
    final userNotes = parsed.userNotes;

    final subtotalCents = returnEntity.subtotalCents.toBigInt().toInt();
    final discountCents = returnEntity.discountCents.toBigInt().toInt();
    final taxCents = returnEntity.taxCents.toBigInt().toInt();
    final totalCents = returnEntity.totalCents.toBigInt().toInt();
    final quantitySummary = localizedQuantitySummary(
      returnItems,
      quantityOf: (entry) => entry.item.quantity,
      measurementTypeOf: (entry) => entry.item.measurementType,
    );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        textDirection: isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _buildHeader(
                company: company,
                title: 'returns.adjustment_detail'.tr(),
                fonts: fonts,
                isRtl: isRtl,
                showLogo: appSettings.showLogoOnReceipt,
              ),
              pw.SizedBox(height: 16),
              // Return info box
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _pdfInfoRow(
                      'purchases.return_number'.tr(),
                      returnEntity.returnNumber,
                      fonts.regular,
                    ),
                    _pdfInfoRow(
                      'purchases.return_date'.tr(),
                      DateFormat('dd/MM/yyyy').format(returnEntity.returnDate),
                      fonts.regular,
                    ),
                    if (supplierName != null && supplierName.isNotEmpty)
                      _pdfInfoRow(
                        'purchases.supplier'.tr(),
                        supplierName,
                        fonts.regular,
                      ),
                    _pdfInfoRow(
                      'purchases.refund_method'.tr(),
                      'purchases.refund_method_${returnEntity.refundMethod}'
                          .tr(),
                      fonts.regular,
                    ),
                    if (reasonText != null)
                      _pdfInfoRow(
                        'returns.reason_label'.tr(),
                        reasonText,
                        fonts.regular,
                      ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),
              // Items table
              _buildAdjReturnItemsTable(
                items: returnItems
                    .map(
                      (d) => _AdjReturnItemRow(
                        name: d.product.name,
                        variantSku: d.variant?.sku,
                        quantity: d.item.quantity,
                        measurementType: d.item.measurementType,
                        unitPriceCents: d.item.unitPriceCents
                            .toBigInt()
                            .toInt(),
                        totalCents: d.item.totalCents.toBigInt().toInt(),
                      ),
                    )
                    .toList(),
                cs: cs,
                fonts: fonts,
              ),
              pw.SizedBox(height: 16),
              // Totals
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.red50,
                  border: pw.Border.all(color: PdfColors.red200),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Column(
                  children: [
                    _pdfMoneyRow(
                      'purchases.total_items_count'.tr(),
                      '${returnItems.length}',
                      fonts.regular,
                    ),
                    _pdfMoneyRow(
                      'measurement.total_quantity'.tr(),
                      quantitySummary,
                      fonts.regular,
                    ),
                    pw.SizedBox(height: 4),
                    if (subtotalCents > 0)
                      _pdfMoneyRow(
                        'purchases.subtotal'.tr(),
                        cs.format(subtotalCents),
                        fonts.regular,
                      ),
                    if (discountCents > 0)
                      _pdfMoneyRow(
                        'purchases.discount'.tr(),
                        '- ${cs.format(discountCents)}',
                        fonts.regular,
                        valueColor: PdfColors.orange,
                      ),
                    if (taxCents > 0)
                      _pdfMoneyRow(
                        'purchases.tax'.tr(),
                        '+ ${cs.format(taxCents)}',
                        fonts.regular,
                      ),
                    pw.Divider(thickness: 2),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        _bidiText(
                          'purchases.return_total'.tr(),
                          fonts.bold,
                          fontSize: 14,
                        ),
                        pw.Text(
                          cs.format(totalCents),
                          style: pw.TextStyle(
                            font: fonts.bold,
                            fontSize: 14,
                            color: PdfColors.red,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (userNotes != null && userNotes.isNotEmpty) ...[
                pw.SizedBox(height: 12),
                pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _bidiText('common.notes'.tr(), fonts.bold, fontSize: 10),
                      pw.SizedBox(height: 4),
                      _bidiText(userNotes, fonts.regular, fontSize: 9),
                    ],
                  ),
                ),
              ],
              if (supplierBalanceWidget != null) ...[
                pw.SizedBox(height: 12),
                supplierBalanceWidget,
              ],
              pw.SizedBox(height: 20),
              _buildFooter(
                fonts: fonts,
                locale: locale,
                receiptFooterText: appSettings.showHeaderFooterOnPurchases
                    ? appSettings.receiptFooterText
                    : null,
              ),
            ],
          );
        },
      ),
    );

    return pdf;
  }

  /// Compact items table shared by purchase/sale adj-return PDFs.
  static pw.Widget _buildAdjReturnItemsTable({
    required List<_AdjReturnItemRow> items,
    required CurrencyService cs,
    required _PdfFonts fonts,
  }) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      columnWidths: {
        0: const pw.FlexColumnWidth(0.6),
        1: const pw.FlexColumnWidth(3),
        2: const pw.FlexColumnWidth(0.8),
        3: const pw.FlexColumnWidth(1.4),
        4: const pw.FlexColumnWidth(1.4),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _tableCell('#', fonts.bold, isHeader: true),
            _tableCell('purchases.product'.tr(), fonts.bold, isHeader: true),
            _tableCell('purchases.qty'.tr(), fonts.bold, isHeader: true),
            _tableCell('purchases.unit_cost'.tr(), fonts.bold, isHeader: true),
            _tableCell('purchases.total'.tr(), fonts.bold, isHeader: true),
          ],
        ),
        ...items.asMap().entries.map((e) {
          final idx = e.key;
          final it = e.value;
          final displayName = it.variantSku != null && it.variantSku!.isNotEmpty
              ? '${it.name} (${it.variantSku})'
              : it.name;
          return pw.TableRow(
            children: [
              _tableCell('${idx + 1}', fonts.regular),
              _tableCell(displayName, fonts.regular),
              _tableCell(
                localizedQuantity(it.quantity, it.measurementType),
                fonts.regular,
              ),
              _tableCell(cs.format(it.unitPriceCents), fonts.regular),
              _tableCell(cs.format(it.totalCents), fonts.regular),
            ],
          );
        }),
      ],
    );
  }
}

/// Lightweight row DTO used by the adj-return items table.
class _AdjReturnItemRow {
  final String name;
  final String? variantSku;
  final int quantity;
  final String measurementType;
  final int unitPriceCents;
  final int totalCents;
  const _AdjReturnItemRow({
    required this.name,
    this.variantSku,
    required this.quantity,
    this.measurementType = 'piece',
    required this.unitPriceCents,
    required this.totalCents,
  });
}

class _PdfFonts {
  final pw.Font regular;
  final pw.Font bold;

  const _PdfFonts({required this.regular, required this.bold});
}

class _PdfLineItem {
  final String name;
  final String? variantSku;
  final int quantity;
  final String measurementType;
  final int unitCostCents;
  final int totalCents;

  const _PdfLineItem({
    required this.name,
    this.variantSku,
    required this.quantity,
    this.measurementType = 'piece',
    required this.unitCostCents,
    required this.totalCents,
  });
}
