import 'package:easy_localization/easy_localization.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/measurement/measurement_localization.dart';
import '../../../core/services/currency_service.dart' as money;
import '../../settings/data/services/company_profile_service.dart';
import '../presentation/bloc/supplier_sales_report_bloc.dart';
import '../presentation/widgets/warehouse_report_context.dart';

String supplierSalesMoney(int cents, String code) {
  final currencies = money.Currency.allCurrencies
      .where((c) => c.code == code)
      .toList();
  if (currencies.length != 1) {
    return '$cents $code (${'supplier_sales.minor_units'.tr()})';
  }
  final digits = currencies.single.decimalDigits;
  final abs = cents.abs().toString().padLeft(digits + 1, '0');
  final value = digits == 0
      ? abs
      : '${abs.substring(0, abs.length - digits)}.${abs.substring(abs.length - digits)}';
  return '${cents < 0 ? '-' : ''}$value $code';
}

class SupplierSalesExportService {
  static List<String> get headers => [
    'supplier',
    'purchase',
    'product',
    'purchased',
    'sold',
    'returned',
    'sales',
    'returns',
    'net',
    'tax',
    'discount',
  ].map((key) => 'supplier_sales.$key'.tr()).toList();
  static List<String> cells(SupplierSalesRow r) => [
    r.supplierId < 0 ? 'supplier_sales.unknown'.tr() : r.supplierName,
    r.purchaseNumber.isEmpty ? '—' : r.purchaseNumber,
    '${r.productName}${r.variantName.isEmpty ? '' : ' • ${r.variantName}'}',
    r.purchaseItemId < 0
        ? '—'
        : localizedQuantity(r.purchasedQuantity, r.measurementType),
    localizedQuantity(r.soldQuantity, r.measurementType),
    localizedQuantity(r.returnedQuantity, r.measurementType),
    supplierSalesMoney(r.salesCents, r.currencyCode),
    supplierSalesMoney(r.returnsCents, r.currencyCode),
    supplierSalesMoney(r.netCents, r.currencyCode),
    supplierSalesMoney(r.taxCents, r.currencyCode),
    supplierSalesMoney(r.discountCents, r.currencyCode),
  ];
  static String filters(SupplierSalesReportData data) => [
    '${DateFormat('yyyy-MM-dd').format(data.range.startDate)} — ${DateFormat('yyyy-MM-dd').format(data.range.endDate)}',
    '${'supplier_sales.supplier'.tr()}: ${data.supplierId == null
        ? 'supplier_sales.all'.tr()
        : data.supplierId == -1
        ? 'supplier_sales.unknown'.tr()
        : data.suppliers[data.supplierId] ?? ''}',
    '${'supplier_sales.category'.tr()}: ${data.categoryId == null ? 'supplier_sales.all'.tr() : data.categories[data.categoryId] ?? ''}',
    '${'supplier_sales.product'.tr()}: ${data.productId == null ? 'supplier_sales.all'.tr() : data.products[data.productId] ?? ''}',
  ].join(' • ');
  static Future<void> export(
    BuildContext context,
    SupplierSalesReportData data, {
    bool excel = false,
    bool share = false,
  }) async {
    final location = WarehouseReportContext.maybeOf(context);
    final rtl = context.locale.languageCode == 'ar';
    final renderBox = context.findRenderObject() as RenderBox?;
    final origin = renderBox == null
        ? null
        : renderBox.localToGlobal(Offset.zero) & renderBox.size;
    await location?.scope.checkAccess();
    final profile = await sl<CompanyProfileService>().getProfile();
    final company = location?.decorateCompany(profile) ?? profile;
    final title = 'reports.sales_by_supplier'.tr();
    final caption = filters(data);
    final note = 'supplier_sales.source_note'.tr();
    final totals = data.netByCurrency.entries
        .map((e) => supplierSalesMoney(e.value, e.key))
        .join(' • ');
    if (excel) {
      final book = Excel.createExcel();
      final sheet = book['Sales by supplier'];
      book.delete('Sheet1');
      for (final text in [company.name, title, caption, note, totals]) {
        sheet.appendRow([TextCellValue(text)]);
      }
      sheet.appendRow(headers.map(TextCellValue.new).toList());
      for (final row in data.rows) {
        sheet.appendRow(cells(row).map(TextCellValue.new).toList());
      }
      await location?.scope.checkAccess();
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              Uint8List.fromList(book.save()!),
              name: 'SupplierSales.xlsx',
              mimeType:
                  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            ),
          ],
          subject: title,
          sharePositionOrigin: origin,
        ),
      );
      return;
    }
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/IBMPlexSansArabic-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/IBMPlexSansArabic-Bold.ttf'),
    );
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        theme: pw.ThemeData.withFont(base: font, bold: bold),
        textDirection: rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        build: (_) => [
          pw.Text(company.name),
          pw.Text(
            title,
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(caption, style: const pw.TextStyle(fontSize: 9)),
          pw.Text(note, style: const pw.TextStyle(fontSize: 9)),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: data.rows.map(cells).toList(),
            cellStyle: const pw.TextStyle(fontSize: 7),
            headerStyle: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Text('${'supplier_sales.net'.tr()}: $totals'),
        ],
      ),
    );
    await location?.scope.checkAccess();
    if (share) {
      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename: 'SupplierSales.pdf',
      );
    } else {
      await Printing.layoutPdf(onLayout: (_) => pdf.save(), name: title);
    }
  }
}
