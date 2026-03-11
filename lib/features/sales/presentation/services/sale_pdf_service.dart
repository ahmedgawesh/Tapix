import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../../../settings/data/services/company_profile_service.dart';
import '../../../settings/domain/entities/company_profile.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/presentation/bloc/app_settings_bloc.dart';
import '../../../customers/domain/repositories/customer_repository.dart';
import '../../domain/entities/sale_entity.dart';
import '../bloc/sale_form_bloc.dart';

class SalePdfService {
  /// Generate and print a sale invoice PDF from current form state
  static Future<void> printFromFormState({
    required BuildContext context,
    required SaleFormState state,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();
    final appSettings = sl<AppSettingsBloc>().state.settings;

    final pdf = await _buildSaleInvoiceFromState(
      state: state,
      cs: cs,
      locale: locale,
      isRtl: isRtl,
      company: company,
      appSettings: appSettings,
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Sale_${state.saleNumber ?? state.saleId ?? 'draft'}',
    );
  }

  /// Generate and share a sale invoice PDF from current form state
  static Future<void> shareFromFormState({
    required BuildContext context,
    required SaleFormState state,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();
    final appSettings = sl<AppSettingsBloc>().state.settings;

    final pdf = await _buildSaleInvoiceFromState(
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
      filename: 'Sale_${state.saleNumber ?? state.saleId ?? 'draft'}.pdf',
    );
  }

  /// Generate and print a sale invoice PDF from entity data (for reprinting)
  static Future<void> printSaleInvoice({
    required BuildContext context,
    required SaleEntity sale,
    required List<SaleItemEntity> items,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();
    final appSettings = sl<AppSettingsBloc>().state.settings;

    final pdf = await _buildSaleInvoiceFromEntity(
      sale: sale,
      items: items,
      cs: cs,
      appSettings: appSettings,
      locale: locale,
      isRtl: isRtl,
      company: company,
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Sale_${sale.invoiceNumber}',
    );
  }

  /// Generate and share a sale invoice PDF from entity data (for sharing)
  static Future<void> shareSaleInvoice({
    required BuildContext context,
    required SaleEntity sale,
    required List<SaleItemEntity> items,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();
    final appSettings = sl<AppSettingsBloc>().state.settings;

    final pdf = await _buildSaleInvoiceFromEntity(
      sale: sale,
      items: items,
      cs: cs,
      appSettings: appSettings,
      locale: locale,
      isRtl: isRtl,
      company: company,
    );

    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'Sale_${sale.invoiceNumber}.pdf',
    );
  }

  /// Generate and print a sale return PDF
  static Future<void> printSaleReturn({
    required BuildContext context,
    required SaleEntity originalSale,
    required SaleReturnEntity returnEntity,
    required List<SaleReturnItemEntity> returnItems,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();

    final pdf = await _buildSaleReturnPdf(
      originalSale: originalSale,
      returnEntity: returnEntity,
      returnItems: returnItems,
      cs: cs,
      locale: locale,
      isRtl: isRtl,
      company: company,
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'SaleReturn_${returnEntity.id}',
    );
  }

  /// Generate and share a sale return PDF
  static Future<void> shareSaleReturn({
    required BuildContext context,
    required SaleEntity originalSale,
    required SaleReturnEntity returnEntity,
    required List<SaleReturnItemEntity> returnItems,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();

    final pdf = await _buildSaleReturnPdf(
      originalSale: originalSale,
      returnEntity: returnEntity,
      returnItems: returnItems,
      cs: cs,
      locale: locale,
      isRtl: isRtl,
      company: company,
    );

    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'SaleReturn_${returnEntity.returnNumber}.pdf',
    );
  }

  // ═══════════════════════════════════════════════════════
  // SALE RETURN PDF
  // ═══════════════════════════════════════════════════════
  static Future<pw.Document> _buildSaleReturnPdf({
    required SaleEntity originalSale,
    required SaleReturnEntity returnEntity,
    required List<SaleReturnItemEntity> returnItems,
    required CurrencyService cs,
    required Locale locale,
    required bool isRtl,
    required CompanyProfile company,
  }) async {
    final fonts = await _loadFonts();
    final pdf = pw.Document();

    // Fetch customer balance for the PDF footer
    pw.Widget? customerBalanceWidget;
    try {
      if (originalSale.customerId != null) {
        final customerRepo = sl<CustomerRepository>();
        final customers = await customerRepo.searchCustomers('');
        final customer = customers.where((c) => c.id == originalSale.customerId).firstOrNull;
        if (customer != null) {
          customerBalanceWidget = _buildCustomerBalance(
            customerName: customer.name,
            balanceCents: customer.balanceCents.toBigInt().toInt(),
            cs: cs,
            fonts: fonts,
            loyaltyPoints: customer.loyaltyPointsBalance,
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
                title: 'sales.sale_return'.tr(),
                fonts: fonts,
                isRtl: isRtl,
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
                    _pdfInfoRow('sales.return_number'.tr(),
                        returnEntity.returnNumber, fonts.regular),
                    _pdfInfoRow('sales.date'.tr(),
                        DateFormat.yMMMd(locale.toString()).format(returnEntity.returnDate),
                        fonts.regular),
                    _pdfInfoRow('sales.return_from_sale'.tr(),
                        originalSale.invoiceNumber.isNotEmpty ? originalSale.invoiceNumber : '${originalSale.id}',
                        fonts.regular),
                    _pdfInfoRow('sales.customer'.tr(),
                        originalSale.customerName ?? 'sales.walk_in'.tr(), fonts.regular),
                    _pdfInfoRow('sales.refund_method'.tr(),
                        'sales.refund_method_${returnEntity.refundMethod}'.tr(),
                        fonts.regular),
                    _pdfInfoRow('sales.disposition_type'.tr(),
                        'sales.disposition_${returnEntity.dispositionType}'.tr(),
                        fonts.regular),
                    if (returnEntity.reason != null && returnEntity.reason!.isNotEmpty)
                      _pdfInfoRow('sales.return_reason'.tr(),
                          returnEntity.reason!, fonts.regular),
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
                    _pdfMoneyRow('sales.total_items_count'.tr(), '${returnItems.length}', fonts.regular),
                    _pdfMoneyRow('sales.total_pieces_count'.tr(), '${returnItems.fold<int>(0, (sum, item) => sum + item.quantity)}', fonts.regular),
                    pw.SizedBox(height: 4),
                    _pdfMoneyRow('sales.subtotal'.tr(), cs.format(returnEntity.subtotalCents.toBigInt().toInt()), fonts.regular),
                    if (returnEntity.discountCents.toBigInt().toInt() > 0)
                      _pdfMoneyRow('sales.discount'.tr(), '- ${cs.format(returnEntity.discountCents.toBigInt().toInt())}', fonts.regular, valueColor: PdfColors.orange),
                    if (returnEntity.taxCents.toBigInt().toInt() > 0)
                      _pdfMoneyRow('sales.tax'.tr(), '+ ${cs.format(returnEntity.taxCents.toBigInt().toInt())}', fonts.regular),
                    pw.Divider(thickness: 2),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        _bidiText('sales.total_refund'.tr(), fonts.bold, fontSize: 14),
                        pw.Text(
                          cs.format(returnEntity.totalCents.toBigInt().toInt()),
                          style: pw.TextStyle(
                            font: fonts.bold, fontSize: 14, color: PdfColors.red,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (customerBalanceWidget != null) ...[
                pw.SizedBox(height: 12),
                customerBalanceWidget,
              ],
              pw.Spacer(),
              _buildFooter(fonts: fonts, locale: locale),
            ],
          );
        },
      ),
    );

    return pdf;
  }

  static pw.Widget _buildReturnItemsTable({
    required List<SaleReturnItemEntity> items,
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
          decoration: const pw.BoxDecoration(color: PdfColors.red100),
          children: [
            _tableCell('#', fonts.bold, isHeader: true),
            _tableCell('sales.product_col'.tr(), fonts.bold, isHeader: true),
            _tableCell('sales.qty_col'.tr(), fonts.bold, isHeader: true),
            _tableCell('sales.discount'.tr(), fonts.bold, isHeader: true),
            _tableCell('sales.tax'.tr(), fonts.bold, isHeader: true),
            _tableCell('sales.customer_refund'.tr(), fonts.bold, isHeader: true),
          ],
        ),
        ...items.asMap().entries.map((entry) {
          final idx = entry.key;
          final item = entry.value;
          // Build rich product name with color/size/SKU
          final productName = item.productName ?? 'Item #${item.saleItemId}';
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
              ? variantParts.join(' \u00b7 ')
              : null;

          return pw.TableRow(
            children: [
              _tableCell('${idx + 1}', fonts.regular),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _bidiText(productName, fonts.regular, fontSize: 8),
                    if (variantLine != null)
                      _bidiText(variantLine, fonts.regular, fontSize: 7, color: PdfColors.grey600),
                  ],
                ),
              ),
              _tableCell('${item.quantity}', fonts.regular),
              _tableCell(
                item.discountCents.toBigInt().toInt() > 0
                    ? cs.format(item.discountCents.toBigInt().toInt())
                    : '-',
                fonts.regular),
              _tableCell(
                item.taxCents.toBigInt().toInt() > 0
                    ? cs.format(item.taxCents.toBigInt().toInt())
                    : '-',
                fonts.regular),
              _tableCell(cs.format(item.refundCents.toBigInt().toInt()), fonts.regular),
            ],
          );
        }),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // SALE INVOICE PDF FROM FORM STATE
  // ═══════════════════════════════════════════════════════
  static Future<pw.Document> _buildSaleInvoiceFromState({
    required SaleFormState state,
    required CurrencyService cs,
    required Locale locale,
    required bool isRtl,
    required CompanyProfile company,
    required AppSettings appSettings,
  }) async {
    final fonts = await _loadFonts();
    final pdf = pw.Document();

    // Fetch customer balance for the PDF footer (best-effort)
    pw.Widget? customerBalanceWidget;
    try {
      if (state.customerId != null) {
        final customerRepo = sl<CustomerRepository>();
        final customers = await customerRepo.searchCustomers('');
        final customer = customers.where((c) => c.id == state.customerId).firstOrNull;
        if (customer != null) {
          customerBalanceWidget = _buildCustomerBalance(
            customerName: customer.name,
            balanceCents: customer.balanceCents.toBigInt().toInt(),
            cs: cs,
            fonts: fonts,
            loyaltyPoints: customer.loyaltyPointsBalance,
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
                title: 'sales.title'.tr(),
                fonts: fonts,
                isRtl: isRtl,
                receiptHeaderText: appSettings.receiptHeaderText,
                taxRegistrationNumber: appSettings.taxRegistrationNumber,
              ),
              pw.SizedBox(height: 16),
              _buildInvoiceInfo(
                invoiceNumber: state.saleNumber ?? '${state.saleId ?? ''}',
                date: state.saleDate,
                customerName: state.customerName ?? 'sales.walk_in'.tr(),
                salespersonName: state.employeeName,
                locale: locale,
                fonts: fonts,
              ),
              pw.SizedBox(height: 16),
              _buildItemsTable(
                items: state.items.map((item) => _PdfLineItem(
                  name: item.product.name,
                  variantSku: item.variant?.sku,
                  colorName: item.colorName,
                  sizeName: item.sizeName,
                  employeeName: item.employeeName,
                  quantity: item.quantity,
                  unitPriceCents: item.unitPriceCents.toBigInt().toInt(),
                  totalCents: item.totalCents.toBigInt().toInt(),
                )).toList(),
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
                paidCents: state.paidAmountCents.toBigInt().toInt(),
                totalItems: state.items.length,
                totalPieces: state.items.fold<int>(0, (sum, item) => sum + item.quantity),
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
                      _bidiText('sales.notes'.tr(), fonts.bold, fontSize: 10),
                      pw.SizedBox(height: 4),
                      _bidiText(state.notes!, fonts.regular, fontSize: 9),
                    ],
                  ),
                ),
              ],
              if (customerBalanceWidget != null) ...[
                pw.SizedBox(height: 12),
                customerBalanceWidget,
              ],
              pw.Spacer(),
              _buildFooter(fonts: fonts, locale: locale, receiptFooterText: appSettings.receiptFooterText),
            ],
          );
        },
      ),
    );

    return pdf;
  }

  // ═══════════════════════════════════════════════════════
  // SALE INVOICE PDF FROM ENTITY DATA (for reprinting)
  // ═══════════════════════════════════════════════════════
  static Future<pw.Document> _buildSaleInvoiceFromEntity({
    required SaleEntity sale,
    required List<SaleItemEntity> items,
    required CurrencyService cs,
    required AppSettings appSettings,
    required Locale locale,
    required bool isRtl,
    required CompanyProfile company,
  }) async {
    final fonts = await _loadFonts();
    final pdf = pw.Document();

    pw.Widget? customerBalanceWidget;
    try {
      if (sale.customerId != null) {
        final customerRepo = sl<CustomerRepository>();
        final customers = await customerRepo.searchCustomers('');
        final customer = customers.where((c) => c.id == sale.customerId).firstOrNull;
        if (customer != null) {
          customerBalanceWidget = _buildCustomerBalance(
            customerName: customer.name,
            balanceCents: customer.balanceCents.toBigInt().toInt(),
            cs: cs,
            fonts: fonts,
            loyaltyPoints: customer.loyaltyPointsBalance,
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
                title: 'sales.title'.tr(),
                fonts: fonts,
                isRtl: isRtl,
                receiptHeaderText: appSettings.receiptHeaderText,
                taxRegistrationNumber: appSettings.taxRegistrationNumber,
              ),
              pw.SizedBox(height: 16),
              _buildInvoiceInfo(
                invoiceNumber: sale.invoiceNumber,
                date: sale.saleDate,
                customerName: sale.customerName ?? 'sales.walk_in'.tr(),
                salespersonName: sale.employeeName,
                locale: locale,
                fonts: fonts,
              ),
              pw.SizedBox(height: 16),
              _buildItemsTable(
                items: items.map((item) => _PdfLineItem(
                  name: item.productName ?? '',
                  variantSku: item.variantSku,
                  colorName: item.colorName,
                  sizeName: item.sizeName,
                  employeeName: item.employeeName,
                  quantity: item.quantity,
                  unitPriceCents: item.unitPriceCents.toBigInt().toInt(),
                  totalCents: item.totalCents.toBigInt().toInt(),
                )).toList(),
                cs: cs,
                fonts: fonts,
                isRtl: isRtl,
              ),
              pw.SizedBox(height: 16),
              _buildTotals(
                subtotalCents: sale.subtotalCents.toBigInt().toInt(),
                discountCents: sale.discountCents.toBigInt().toInt(),
                taxCents: sale.taxCents.toBigInt().toInt(),
                totalCents: sale.totalCents.toBigInt().toInt(),
                paidCents: sale.paidAmountCents.toBigInt().toInt(),
                totalItems: items.length,
                totalPieces: items.fold<int>(0, (sum, item) => sum + item.quantity),
                cs: cs,
                fonts: fonts,
                includeTaxBreakdown: appSettings.includeTaxBreakdown,
              ),
              if (sale.notes != null && sale.notes!.isNotEmpty) ...[
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
                      _bidiText('sales.notes'.tr(), fonts.bold, fontSize: 10),
                      pw.SizedBox(height: 4),
                      _bidiText(sale.notes!, fonts.regular, fontSize: 9),
                    ],
                  ),
                ),
              ],
              if (customerBalanceWidget != null) ...[
                pw.SizedBox(height: 12),
                customerBalanceWidget,
              ],
              pw.Spacer(),
              _buildFooter(fonts: fonts, locale: locale, receiptFooterText: appSettings.receiptFooterText),
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
    final fontData = await rootBundle.load('assets/fonts/IBMPlexSansArabic-Regular.ttf');
    final fontBoldData = await rootBundle.load('assets/fonts/IBMPlexSansArabic-Bold.ttf');
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
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: PdfColors.green50,
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
                  if (company.name.isNotEmpty)
                    _bidiText(company.name, fonts.bold, fontSize: 16),
                  if (company.address != null && company.address!.isNotEmpty)
                    _bidiText(company.address!, fonts.regular, fontSize: 8, color: PdfColors.grey600),
                  if (company.phone != null && company.phone!.isNotEmpty)
                    _bidiText(company.phone!, fonts.regular, fontSize: 8, color: PdfColors.grey600),
                  // Use taxRegistrationNumber from AppSettings if available, fallback to company.taxNumber
                  if ((taxRegistrationNumber != null && taxRegistrationNumber.isNotEmpty) ||
                      (company.taxNumber != null && company.taxNumber!.isNotEmpty))
                    _bidiText('Tax: ${taxRegistrationNumber ?? company.taxNumber}', fonts.regular, fontSize: 8, color: PdfColors.grey600),
                ],
              ),
              _bidiText(title, fonts.bold, fontSize: 20, color: PdfColors.green800),
            ],
          ),
          // Custom header text from AppSettings
          if (receiptHeaderText != null && receiptHeaderText.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            _bidiText(receiptHeaderText, fonts.regular, fontSize: 9, color: PdfColors.grey700),
          ],
        ],
      ),
    );
  }

  static pw.Widget _buildInvoiceInfo({
    required String invoiceNumber,
    required DateTime date,
    required String customerName,
    String? salespersonName,
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
          _pdfInfoRow('sales.invoice_number'.tr(), invoiceNumber, fonts.regular),
          _pdfInfoRow('sales.invoice_date'.tr(),
              DateFormat.yMMMd(locale.toString()).format(date), fonts.regular),
          _pdfInfoRow('sales.customer'.tr(), customerName, fonts.regular),
          if (salespersonName != null && salespersonName.isNotEmpty)
            _pdfInfoRow('sales.salesperson'.tr(), salespersonName, fonts.regular),
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
    final hasPerItemSalesperson = items.any((i) => i.employeeName != null && i.employeeName!.isNotEmpty);

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      columnWidths: hasPerItemSalesperson
          ? {
              0: const pw.FlexColumnWidth(0.8),
              1: const pw.FlexColumnWidth(2.5),
              2: const pw.FlexColumnWidth(1.5),
              3: const pw.FlexColumnWidth(0.8),
              4: const pw.FlexColumnWidth(1.3),
              5: const pw.FlexColumnWidth(1.3),
            }
          : {
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
            _tableCell('sales.product_col'.tr(), fonts.bold, isHeader: true),
            if (hasPerItemSalesperson)
              _tableCell('sales.salesperson'.tr(), fonts.bold, isHeader: true),
            _tableCell('sales.qty_col'.tr(), fonts.bold, isHeader: true),
            _tableCell('sales.unit_price'.tr(), fonts.bold, isHeader: true),
            _tableCell('sales.total'.tr(), fonts.bold, isHeader: true),
          ],
        ),
        // Items
        ...items.asMap().entries.map((entry) {
          final idx = entry.key;
          final item = entry.value;
          final displayName = item.displayName;
          return pw.TableRow(
            children: [
              _tableCell('${idx + 1}', fonts.regular),
              _tableCell(displayName, fonts.regular),
              if (hasPerItemSalesperson)
                _tableCell(item.employeeName ?? '', fonts.regular),
              _tableCell('${item.quantity}', fonts.regular),
              _tableCell(cs.format(item.unitPriceCents), fonts.regular),
              _tableCell(cs.format(item.totalCents), fonts.regular),
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
    required int paidCents,
    required int totalItems,
    required int totalPieces,
    required CurrencyService cs,
    required _PdfFonts fonts,
    bool includeTaxBreakdown = true,
  }) {
    final remainingCents = totalCents - paidCents;
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.green50,
        border: pw.Border.all(color: PdfColors.green200),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        children: [
          _pdfMoneyRow('sales.total_items_count'.tr(), '$totalItems', fonts.regular),
          _pdfMoneyRow('sales.total_pieces_count'.tr(), '$totalPieces', fonts.regular),
          pw.SizedBox(height: 4),
          _pdfMoneyRow('sales.subtotal'.tr(), cs.format(subtotalCents), fonts.regular),
          if (discountCents > 0)
            _pdfMoneyRow('sales.discount'.tr(), '- ${cs.format(discountCents)}',
                fonts.regular, valueColor: PdfColors.orange),
          // Only show tax breakdown if includeTaxBreakdown is true
          if (taxCents > 0 && includeTaxBreakdown)
            _pdfMoneyRow('sales.tax'.tr(), cs.format(taxCents), fonts.regular),
          pw.Divider(thickness: 2),
          _pdfMoneyRow('sales.total'.tr(), cs.format(totalCents),
              fonts.bold, fontSize: 14),
          if (paidCents > 0) ...[
            pw.SizedBox(height: 4),
            _pdfMoneyRow('sales.paid_amount'.tr(), cs.format(paidCents), fonts.regular),
            if (remainingCents > 0)
              _pdfMoneyRow(
                'sales.remaining'.tr(),
                cs.format(remainingCents),
                fonts.bold,
                valueColor: PdfColors.red,
              ),
            if (remainingCents < 0)
              _pdfMoneyRow(
                'sales.change'.tr(),
                cs.format(-remainingCents),
                fonts.bold,
                valueColor: PdfColors.green700,
              ),
          ],
        ],
      ),
    );
  }

  static pw.Widget _buildCustomerBalance({
    required String customerName,
    required int balanceCents,
    required CurrencyService cs,
    required _PdfFonts fonts,
    int loyaltyPoints = 0,
  }) {
    final hasBalance = balanceCents != 0;
    final isOwed = balanceCents > 0; // positive = customer owes us
    final absBalance = balanceCents.abs();
    final balanceLabel = isOwed
        ? 'sales.customer_owes'.tr()
        : 'sales.customer_credit'.tr();
    final balanceColor = isOwed ? PdfColors.red700 : PdfColors.green700;

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
              _bidiText('sales.customer_account'.tr(), fonts.bold, fontSize: 9),
              _bidiText(customerName, fonts.regular, fontSize: 8, color: PdfColors.grey600),
              if (loyaltyPoints > 0) ...[
                pw.SizedBox(height: 4),
                pw.Row(
                  children: [
                    _bidiText('sales.loyalty_points_balance'.tr(), fonts.regular, fontSize: 8, color: PdfColors.amber800),
                    pw.SizedBox(width: 4),
                    pw.Text(
                      '$loyaltyPoints',
                      style: pw.TextStyle(font: fonts.bold, fontSize: 9, color: PdfColors.amber800),
                    ),
                  ],
                ),
              ],
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              _bidiText(
                hasBalance ? balanceLabel : 'sales.balance_zero'.tr(),
                fonts.regular,
                fontSize: 8,
                color: PdfColors.grey600,
              ),
              pw.Text(
                cs.format(absBalance),
                style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: 11,
                  color: hasBalance ? balanceColor : PdfColors.grey700,
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
    final generatedText = '${'sales.generated_on'.tr()}: ${DateFormat('yyyy-MM-dd HH:mm', locale.toString()).format(DateTime.now())}';
    return pw.Column(
      children: [
        // Custom footer text from AppSettings
        if (receiptFooterText != null && receiptFooterText.isNotEmpty) ...[
          _bidiText(receiptFooterText, fonts.regular, fontSize: 9, color: PdfColors.grey700),
          pw.SizedBox(height: 4),
        ],
        pw.Container(
          alignment: pw.Alignment.center,
          child: _bidiText(generatedText, fonts.regular, fontSize: 8, color: PdfColors.grey500),
        ),
      ],
    );
  }

  /// Detect if text contains Arabic/Hebrew characters that need RTL
  static bool _hasArabic(String text) {
    return RegExp(r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF\u0590-\u05FF]').hasMatch(text);
  }

  /// Create a pw.Text that auto-detects Arabic and sets textDirection accordingly
  static pw.Text _bidiText(String text, pw.Font font, {double fontSize = 8, PdfColor? color}) {
    return pw.Text(text,
        textDirection: _hasArabic(text) ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        style: pw.TextStyle(font: font, fontSize: fontSize, color: color));
  }

  static pw.Widget _tableCell(String text, pw.Font font, {bool isHeader = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: _bidiText(text, font, fontSize: isHeader ? 9 : 8),
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

  static pw.Widget _pdfMoneyRow(String label, String value, pw.Font font,
      {PdfColor? valueColor, double fontSize = 10}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          _bidiText(label, font, fontSize: fontSize),
          pw.Text(value,
              style: pw.TextStyle(
                font: font, fontSize: fontSize,
                color: valueColor,
              )),
        ],
      ),
    );
  }
}

class _PdfFonts {
  final pw.Font regular;
  final pw.Font bold;

  const _PdfFonts({required this.regular, required this.bold});
}

class _PdfLineItem {
  final String name;
  final String? variantSku;
  final String? colorName;
  final String? sizeName;
  final String? employeeName;
  final int quantity;
  final int unitPriceCents;
  final int totalCents;

  const _PdfLineItem({
    required this.name,
    this.variantSku,
    this.colorName,
    this.sizeName,
    this.employeeName,
    required this.quantity,
    required this.unitPriceCents,
    required this.totalCents,
  });

  String get displayName {
    final parts = <String>[];
    if (colorName != null) parts.add(colorName!);
    if (sizeName != null) parts.add(sizeName!);
    if (parts.isEmpty && variantSku != null) {
      parts.add(variantSku!);
    }
    if (parts.isNotEmpty) {
      return '$name (${parts.join(' / ')})';
    }
    return name;
  }
}
