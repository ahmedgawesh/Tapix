import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/di/injection_container.dart';
import '../../../core/services/currency_service.dart';
import '../presentation/bloc/supplier_balance_report_bloc.dart';

/// Service for exporting supplier balance reports to Excel format.
class SupplierBalanceExcelService {
  /// Export the full supplier balance report to Excel and share it.
  static Future<void> shareSupplierBalanceReport({
    required BuildContext context,
    required SupplierBalanceReportData data,
  }) async {
    final cs = sl<CurrencyService>();
    final bytes = _buildFullReportExcel(data: data, cs: cs);
    final filename =
        'SupplierBalanceReport_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx';

    final xFile = XFile.fromData(
      bytes,
      name: filename,
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );

    await SharePlus.instance.share(
      ShareParams(
        files: [xFile],
        subject: 'reports.supplier_balance_report'.tr(),
      ),
    );
  }

  /// Export a single supplier balance detail to Excel and share it.
  static Future<void> shareSupplierDetail({
    required BuildContext context,
    required SupplierBalanceItem item,
  }) async {
    final cs = sl<CurrencyService>();
    final bytes = _buildSingleSupplierExcel(item: item, cs: cs);
    final safeName = item.supplierName.replaceAll(RegExp(r'[^\w\s]'), '_');
    final filename =
        'SupplierBalance_${safeName}_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx';

    final xFile = XFile.fromData(
      bytes,
      name: filename,
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );

    await SharePlus.instance.share(
      ShareParams(
        files: [xFile],
        subject:
            '${'reports.supplier_balance_report'.tr()} - ${item.supplierName}',
      ),
    );
  }

  // ─── Full report Excel ─────────────────────────────────

  static Uint8List _buildFullReportExcel({
    required SupplierBalanceReportData data,
    required CurrencyService cs,
  }) {
    final excel = Excel.createExcel();
    final sheet = excel['Supplier Balances'];

    // Summary header rows
    sheet.appendRow([TextCellValue('reports.supplier_balance_report'.tr())]);
    sheet.appendRow([
      TextCellValue(
        '${DateFormat('dd/MM/yyyy').format(data.dateRange.startDate)} - ${DateFormat('dd/MM/yyyy').format(data.dateRange.endDate)}',
      ),
    ]);
    sheet.appendRow([]); // blank row

    // Summary
    sheet.appendRow([
      TextCellValue('reports.total_payables'.tr()),
      TextCellValue(cs.formatCents(data.summary.totalPayablesCents)),
    ]);
    sheet.appendRow([
      TextCellValue('reports.total_receivables'.tr()),
      TextCellValue(cs.formatCents(data.summary.totalReceivablesCents)),
    ]);
    sheet.appendRow([
      TextCellValue('reports.net_balance'.tr()),
      TextCellValue(cs.formatCents(data.summary.netBalanceCents)),
    ]);
    sheet.appendRow([]); // blank row

    // Table headers
    sheet.appendRow([
      TextCellValue('reports.supplier_name'.tr()),
      TextCellValue('reports.opening_balance'.tr()),
      TextCellValue('reports.total_purchases'.tr()),
      TextCellValue('reports.total_payments'.tr()),
      TextCellValue('reports.total_returns'.tr()),
      TextCellValue('reports.total_discounts'.tr()),
      TextCellValue('reports.net_balance'.tr()),
      TextCellValue('reports.transaction_count'.tr()),
    ]);

    // Data rows
    for (final s in data.filteredSuppliers) {
      sheet.appendRow([
        TextCellValue(s.supplierName),
        TextCellValue(cs.formatCents(s.openingBalanceCents)),
        TextCellValue(cs.formatCents(s.totalPurchasesCents)),
        TextCellValue(cs.formatCents(s.totalPaymentsCents)),
        TextCellValue(cs.formatCents(s.totalReturnsCents)),
        TextCellValue(cs.formatCents(s.totalDiscountsCents)),
        TextCellValue(cs.formatCents(s.netBalanceCents)),
        IntCellValue(s.transactionCount),
      ]);
    }

    // Remove the default Sheet1 if it exists and isn't our sheet
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final fileBytes = excel.encode();
    if (fileBytes == null) {
      throw Exception('Failed to encode Excel file');
    }
    return Uint8List.fromList(fileBytes);
  }

  // ─── Single supplier Excel ─────────────────────────────

  static Uint8List _buildSingleSupplierExcel({
    required SupplierBalanceItem item,
    required CurrencyService cs,
  }) {
    final excel = Excel.createExcel();
    final sheet = excel[item.supplierName];

    // Supplier header
    sheet.appendRow([TextCellValue(item.supplierName)]);
    if (item.phone != null) {
      sheet.appendRow([TextCellValue(item.phone!)]);
    }
    if (item.email != null) {
      sheet.appendRow([TextCellValue(item.email!)]);
    }
    sheet.appendRow([]); // blank row

    // Balance breakdown
    sheet.appendRow([
      TextCellValue('reports.net_balance'.tr()),
      TextCellValue(cs.formatCents(item.netBalanceCents)),
    ]);
    sheet.appendRow([
      TextCellValue(
        item.isPayable
            ? 'reports.payable'.tr()
            : item.isReceivable
            ? 'reports.receivable'.tr()
            : 'reports.settled'.tr(),
      ),
    ]);
    sheet.appendRow([]); // blank row

    // Detailed breakdown table
    sheet.appendRow([TextCellValue('reports.balance_breakdown'.tr())]);
    sheet.appendRow([
      TextCellValue('reports.opening_balance'.tr()),
      TextCellValue(cs.formatCents(item.openingBalanceCents)),
    ]);
    sheet.appendRow([
      TextCellValue('reports.total_purchases'.tr()),
      TextCellValue('+ ${cs.formatCents(item.totalPurchasesCents)}'),
    ]);
    sheet.appendRow([
      TextCellValue('reports.total_payments'.tr()),
      TextCellValue('- ${cs.formatCents(item.totalPaymentsCents)}'),
    ]);
    sheet.appendRow([
      TextCellValue('reports.total_returns'.tr()),
      TextCellValue('- ${cs.formatCents(item.totalReturnsCents)}'),
    ]);
    sheet.appendRow([
      TextCellValue('reports.total_discounts'.tr()),
      TextCellValue('- ${cs.formatCents(item.totalDiscountsCents)}'),
    ]);
    sheet.appendRow([]); // blank row
    sheet.appendRow([
      TextCellValue('reports.net_balance'.tr()),
      TextCellValue(cs.formatCents(item.netBalanceCents)),
    ]);

    // Remove the default Sheet1 if it exists and isn't our sheet
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final fileBytes = excel.encode();
    if (fileBytes == null) {
      throw Exception('Failed to encode Excel file');
    }
    return Uint8List.fromList(fileBytes);
  }
}
