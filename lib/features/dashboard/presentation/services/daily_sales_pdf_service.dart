import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart' hide TextDirection;
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:ui' as ui;

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../../../settings/data/services/company_profile_service.dart';
import 'daily_sales_reporting_service.dart';

class _PdfFonts {
  final pw.Font regular;
  final pw.Font bold;
  _PdfFonts({required this.regular, required this.bold});
}

class DailySalesPdfService {
  static Future<_PdfFonts> _loadFonts() async {
    try {
      final regularData = await rootBundle.load(
        'assets/fonts/IBMPlexSansArabic-Regular.ttf',
      );
      final boldData = await rootBundle.load(
        'assets/fonts/IBMPlexSansArabic-Bold.ttf',
      );
      return _PdfFonts(
        regular: pw.Font.ttf(regularData),
        bold: pw.Font.ttf(boldData),
      );
    } catch (_) {
      return _PdfFonts(
        regular: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
      );
    }
  }

  static Future<void> printDailySummary({required BuildContext context}) async {
    // Capture RTL before async gap
    final textDir = Directionality.of(context);
    final isRtl = textDir == ui.TextDirection.rtl;
    final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;

    final db = sl<AppDatabase>();
    final cs = sl<CurrencyService>();
    final company = await sl<CompanyProfileService>().getProfile();
    final fonts = await _loadFonts();

    final today = DateTime.now();
    // Fetch sales and both return types from the same read model used by the
    // dashboard card so printed totals can never disagree with the screen.
    List<DailySalesReportRow> salesData;
    try {
      salesData = await DailySalesReportingService(db).loadDay(today);
    } catch (e) {
      debugPrint('Error fetching sales data: $e');
      rethrow;
    }

    final pdf = pw.Document();

    // Calculate totals
    int totalSales = 0;
    int totalRevenue = 0;
    int totalCost = 0;
    int totalDiscount = 0;
    int totalTax = 0;

    for (final row in salesData) {
      totalSales += row.grossCents;
      totalRevenue += row.revenueCents;
      totalCost += row.costCents;
      totalDiscount += row.discountCents;
      totalTax += row.taxCents;
    }

    final totalProfit = totalRevenue - totalCost;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        textDirection: dir,
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: dir,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Header
                pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.blue50,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        company.name,
                        style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          font: fonts.bold,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'dashboard.daily_sales_summary'.tr(),
                        style: pw.TextStyle(
                          fontSize: 14,
                          color: PdfColors.blue800,
                          font: fonts.regular,
                        ),
                      ),
                      pw.Text(
                        DateFormat('EEEE, MMMM d, yyyy').format(today),
                        style: pw.TextStyle(
                          fontSize: 12,
                          color: PdfColors.grey700,
                          font: fonts.regular,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 20),

                // Summary stats
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.green50,
                    border: pw.Border.all(color: PdfColors.green200),
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: pw.Column(
                    children: [
                      _buildSummaryRow(
                        'dashboard.sales_count'.tr(),
                        '${salesData.where((r) => r.documentType == 'sale').length}',
                        fonts,
                      ),
                      pw.Divider(),
                      _buildSummaryRow(
                        'dashboard.total_sales'.tr(),
                        cs.format(totalSales),
                        fonts,
                      ),
                      _buildSummaryRow(
                        'dashboard.total_revenue'.tr(),
                        cs.format(totalRevenue),
                        fonts,
                      ),
                      _buildSummaryRow(
                        'dashboard.total_cost'.tr(),
                        cs.format(totalCost),
                        fonts,
                      ),
                      if (totalDiscount > 0)
                        _buildSummaryRow(
                          'sales.discount'.tr(),
                          cs.format(totalDiscount),
                          fonts,
                        ),
                      if (totalTax > 0)
                        _buildSummaryRow(
                          'sales.tax'.tr(),
                          cs.format(totalTax),
                          fonts,
                        ),
                      pw.Divider(thickness: 2),
                      _buildSummaryRow(
                        'dashboard.profit'.tr(),
                        cs.format(totalProfit),
                        fonts,
                        isBold: true,
                        color: totalProfit >= 0
                            ? PdfColors.green
                            : PdfColors.red,
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 20),

                // Sales table
                if (salesData.isNotEmpty) ...[
                  pw.Text(
                    'dashboard.sales_details'.tr(),
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      font: fonts.bold,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.grey300),
                    children: [
                      // Header
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(
                          color: PdfColors.grey200,
                        ),
                        children: [
                          _buildTableCell(
                            'sales.sale_number'.tr(),
                            fonts,
                            isHeader: true,
                          ),
                          _buildTableCell(
                            'common.time'.tr(),
                            fonts,
                            isHeader: true,
                          ),
                          _buildTableCell(
                            'customers.customer'.tr(),
                            fonts,
                            isHeader: true,
                          ),
                          _buildTableCell(
                            'sales.payment_method'.tr(),
                            fonts,
                            isHeader: true,
                          ),
                          _buildTableCell(
                            'sales.total'.tr(),
                            fonts,
                            isHeader: true,
                          ),
                        ],
                      ),
                      // Data rows
                      ...salesData.map((row) {
                        final invoiceNumber = row.documentNumber;
                        final saleDate = row.documentDate;
                        final customerName =
                            row.customerName ?? 'common.guest'.tr();
                        final paymentMethod = row.paymentMethod;
                        final total = row.grossCents;

                        return pw.TableRow(
                          children: [
                            _buildTableCell(invoiceNumber, fonts),
                            _buildTableCell(
                              DateFormat('HH:mm').format(saleDate),
                              fonts,
                            ),
                            _buildTableCell(customerName, fonts),
                            _buildTableCell(
                              _translatePaymentMethod(paymentMethod),
                              fonts,
                            ),
                            _buildTableCell(
                              cs.format(total),
                              fonts,
                              align: pw.TextAlign.right,
                            ),
                          ],
                        );
                      }),
                    ],
                  ),
                ],

                pw.Spacer(),

                // Footer
                pw.Container(
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    '${'dashboard.generated_on'.tr()}: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
                    style: pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey500,
                      font: fonts.regular,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    try {
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
      );
    } catch (e) {
      debugPrint('Error printing PDF: $e');
      rethrow;
    }
  }

  static pw.Widget _buildSummaryRow(
    String label,
    String value,
    _PdfFonts fonts, {
    bool isBold = false,
    PdfColor? color,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: isBold ? 12 : 10,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              font: isBold ? fonts.bold : fonts.regular,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: isBold ? 12 : 10,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              font: isBold ? fonts.bold : fonts.regular,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildTableCell(
    String text,
    _PdfFonts fonts, {
    bool isHeader = false,
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: isHeader ? 10 : 9,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
          font: isHeader ? fonts.bold : fonts.regular,
        ),
        textAlign: align,
      ),
    );
  }

  static String _translatePaymentMethod(String method) {
    switch (method) {
      case 'cash':
        return 'payments.method_cash'.tr();
      case 'card':
        return 'payments.method_card'.tr();
      case 'bank_transfer':
        return 'payments.method_bank'.tr();
      case 'credit':
        return 'payments.method_credit'.tr();
      default:
        return method;
    }
  }
}
