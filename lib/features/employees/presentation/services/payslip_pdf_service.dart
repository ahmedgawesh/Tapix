import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../../domain/services/payroll_calculation_service.dart';

class PayslipPdfService {
  static Future<void> generateAndPrint({
    required BuildContext context,
    required Employee employee,
    Role? role,
    required String period,
    required Map<String, int> attendanceCounts,
    Payroll? payroll,
    required int totalCommissionCents,
    required List<LeaveRequest> leaveRequests,
    SalesTargetBonusResult? salesTargetBonus,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';

    final pdf = pw.Document();

    final bonus = payroll?.bonusCents.toBigInt().toInt() ?? 0;
    final overtime = payroll?.overtimeCents.toBigInt().toInt() ?? 0;

    final calc = PayrollCalculationService.calculate(
      employee: employee,
      attendanceCounts: attendanceCounts,
      commissionCents: totalCommissionCents,
      bonusCents: bonus,
      overtimeCents: overtime,
    );

    final presentCount = calc.presentDays;
    final lateCount = calc.lateDays;
    final absentCount = calc.absentDays;
    final leaveCount = calc.leaveDays;

    final approvedLeaves = leaveRequests
        .where((l) => l.status == 'approved')
        .length;
    final totalLeaveDays = leaveRequests
        .where((l) => l.status == 'approved')
        .fold<int>(0, (sum, l) => sum + l.daysCount);

    final parts = period.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final periodDisplay = DateFormat(
      'MMMM yyyy',
      locale.toString(),
    ).format(DateTime(year, month));

    final fontData = await rootBundle.load(
      'assets/fonts/IBMPlexSansArabic-Regular.ttf',
    );
    final fontBoldData = await rootBundle.load(
      'assets/fonts/IBMPlexSansArabic-Bold.ttf',
    );
    final font = pw.Font.ttf(fontData);
    final fontBold = pw.Font.ttf(fontBoldData);

    final baseStyle = pw.TextStyle(font: font, fontSize: 10);
    final boldStyle = pw.TextStyle(font: fontBold, fontSize: 10);
    final subHeaderStyle = pw.TextStyle(font: fontBold, fontSize: 11);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        build: (pw.Context ctx) {
          return [
            // Header
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: PdfColors.blue50,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                children: [
                  pw.Text(
                    'employees.payslip'.tr(),
                    style: pw.TextStyle(font: fontBold, fontSize: 20),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(periodDisplay, style: subHeaderStyle),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // Employee Info
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('employees.basic_info'.tr(), style: subHeaderStyle),
                  pw.SizedBox(height: 8),
                  _pdfInfoRow('employees.name'.tr(), employee.name, baseStyle),
                  if (employee.position != null)
                    _pdfInfoRow(
                      'employees.position'.tr(),
                      employee.position!,
                      baseStyle,
                    ),
                  if (employee.department != null)
                    _pdfInfoRow(
                      'employees.department'.tr(),
                      employee.department!,
                      baseStyle,
                    ),
                  if (employee.employeeCode != null)
                    _pdfInfoRow(
                      'employees.employee_code'.tr(),
                      employee.employeeCode!,
                      baseStyle,
                    ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // Attendance Summary
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'employees.attendance_summary'.tr(),
                    style: subHeaderStyle,
                  ),
                  pw.SizedBox(height: 8),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                    children: [
                      _pdfStatBox(
                        'employees.status_present'.tr(),
                        presentCount.toString(),
                        PdfColors.green,
                        baseStyle,
                        boldStyle,
                      ),
                      _pdfStatBox(
                        'employees.status_late'.tr(),
                        lateCount.toString(),
                        PdfColors.orange,
                        baseStyle,
                        boldStyle,
                      ),
                      _pdfStatBox(
                        'employees.status_absent'.tr(),
                        absentCount.toString(),
                        PdfColors.red,
                        baseStyle,
                        boldStyle,
                      ),
                      _pdfStatBox(
                        'employees.status_on_leave'.tr(),
                        leaveCount.toString(),
                        PdfColors.blue,
                        baseStyle,
                        boldStyle,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // Leave Summary
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'employees.leave_summary'.tr(),
                    style: subHeaderStyle,
                  ),
                  pw.SizedBox(height: 8),
                  _pdfInfoRow(
                    'employees.leave_status_approved'.tr(),
                    approvedLeaves.toString(),
                    baseStyle,
                  ),
                  _pdfInfoRow(
                    'employees.total_leave_days'.tr(),
                    totalLeaveDays.toString(),
                    baseStyle,
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // Sales Target
            if (salesTargetBonus != null &&
                salesTargetBonus.salesTargetCents > 0) ...[
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(
                    color: salesTargetBonus.achieved
                        ? PdfColors.green300
                        : PdfColors.orange300,
                  ),
                  borderRadius: pw.BorderRadius.circular(6),
                  color: salesTargetBonus.achieved
                      ? PdfColors.green50
                      : PdfColors.orange50,
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      salesTargetBonus.achieved
                          ? 'employees.target_achieved'.tr()
                          : 'employees.target_not_achieved'.tr(),
                      style: subHeaderStyle.copyWith(
                        color: salesTargetBonus.achieved
                            ? PdfColors.green800
                            : PdfColors.orange800,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    _pdfMoneyRow(
                      'employees.sales_target'.tr(),
                      cs.format(salesTargetBonus.salesTargetCents),
                      baseStyle,
                    ),
                    _pdfMoneyRow(
                      'employees.actual_sales'.tr(),
                      cs.format(salesTargetBonus.actualSalesCents),
                      baseStyle,
                    ),
                    if (salesTargetBonus.achieved)
                      _pdfMoneyRow(
                        'employees.target_bonus'.tr(),
                        '+ ${cs.format(salesTargetBonus.targetBonusCents)}',
                        boldStyle,
                        valueColor: PdfColors.green800,
                      ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),
            ],

            // Salary Breakdown
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.blue200),
                borderRadius: pw.BorderRadius.circular(6),
                color: PdfColors.blue50,
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'employees.payslip_summary'.tr(),
                    style: subHeaderStyle,
                  ),
                  pw.SizedBox(height: 8),
                  _pdfMoneyRow(
                    'employees.basic_salary'.tr(),
                    cs.format(calc.basicSalaryCents),
                    baseStyle,
                  ),
                  _pdfMoneyRow(
                    'employees.total_commission'.tr(),
                    cs.format(calc.commissionCents),
                    baseStyle,
                  ),
                  _pdfMoneyRow(
                    'employees.bonus'.tr(),
                    cs.format(calc.bonusCents),
                    baseStyle,
                  ),
                  _pdfMoneyRow(
                    'employees.overtime_pay'.tr(),
                    cs.format(calc.overtimeCents),
                    baseStyle,
                  ),
                  pw.Divider(),
                  _pdfMoneyRow(
                    'employees.gross_pay'.tr(),
                    cs.format(calc.grossPayCents),
                    boldStyle,
                  ),
                  if (calc.absenceDeductionCents > 0)
                    _pdfMoneyRow(
                      'employees.absence_deduction'.tr(),
                      '- ${cs.format(calc.absenceDeductionCents)}',
                      baseStyle,
                      valueColor: PdfColors.red,
                    ),
                  if (calc.lateDeductionCents > 0)
                    _pdfMoneyRow(
                      'employees.late_deduction'.tr(),
                      '- ${cs.format(calc.lateDeductionCents)}',
                      baseStyle,
                      valueColor: PdfColors.orange,
                    ),
                  _pdfMoneyRow(
                    'employees.total_deductions'.tr(),
                    '- ${cs.format(calc.totalDeductionCents)}',
                    boldStyle,
                    valueColor: PdfColors.red,
                  ),
                  pw.Divider(thickness: 2),
                  _pdfMoneyRow(
                    'employees.net_pay'.tr(),
                    cs.format(calc.netPayCents),
                    pw.TextStyle(font: fontBold, fontSize: 14),
                    valueColor: PdfColors.green800,
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 24),

            // Footer
            pw.Container(
              alignment: pw.Alignment.center,
              child: pw.Text(
                '${'employees.generated_on'.tr()}: ${DateFormat('yyyy-MM-dd HH:mm', locale.toString()).format(DateTime.now())}',
                style: pw.TextStyle(
                  font: font,
                  fontSize: 8,
                  color: PdfColors.grey500,
                ),
              ),
            ),
          ];
        },
      ),
    );

    final pdfBytes = await pdf.save();
    final fileName = '${employee.name}_payslip_$period.pdf';

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfBytes,
      name: fileName,
    );
  }

  static Future<void> generateAndShare({
    required BuildContext context,
    required Employee employee,
    Role? role,
    required String period,
    required Map<String, int> attendanceCounts,
    Payroll? payroll,
    required int totalCommissionCents,
    required List<LeaveRequest> leaveRequests,
    SalesTargetBonusResult? salesTargetBonus,
  }) async {
    final pdfBytes = await _generatePdfBytes(
      context: context,
      employee: employee,
      role: role,
      period: period,
      attendanceCounts: attendanceCounts,
      payroll: payroll,
      totalCommissionCents: totalCommissionCents,
      leaveRequests: leaveRequests,
      salesTargetBonus: salesTargetBonus,
    );

    final dir = await getTemporaryDirectory();
    final fileName = '${employee.name}_payslip_$period.pdf';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(pdfBytes);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: '${'employees.payslip'.tr()} - ${employee.name} - $period',
      ),
    );
  }

  static Future<List<int>> _generatePdfBytes({
    required BuildContext context,
    required Employee employee,
    Role? role,
    required String period,
    required Map<String, int> attendanceCounts,
    Payroll? payroll,
    required int totalCommissionCents,
    required List<LeaveRequest> leaveRequests,
    SalesTargetBonusResult? salesTargetBonus,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';

    final pdf = pw.Document();

    final bonus = payroll?.bonusCents.toBigInt().toInt() ?? 0;
    final overtime = payroll?.overtimeCents.toBigInt().toInt() ?? 0;

    final calc = PayrollCalculationService.calculate(
      employee: employee,
      attendanceCounts: attendanceCounts,
      commissionCents: totalCommissionCents,
      bonusCents: bonus,
      overtimeCents: overtime,
    );

    final presentCount = calc.presentDays;
    final lateCount = calc.lateDays;
    final absentCount = calc.absentDays;
    final leaveCount = calc.leaveDays;

    final approvedLeaves = leaveRequests
        .where((l) => l.status == 'approved')
        .length;
    final totalLeaveDays = leaveRequests
        .where((l) => l.status == 'approved')
        .fold<int>(0, (sum, l) => sum + l.daysCount);

    final parts = period.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final periodDisplay = DateFormat(
      'MMMM yyyy',
      locale.toString(),
    ).format(DateTime(year, month));

    final fontData = await rootBundle.load(
      'assets/fonts/IBMPlexSansArabic-Regular.ttf',
    );
    final fontBoldData = await rootBundle.load(
      'assets/fonts/IBMPlexSansArabic-Bold.ttf',
    );
    final font = pw.Font.ttf(fontData);
    final fontBold = pw.Font.ttf(fontBoldData);

    final baseStyle = pw.TextStyle(font: font, fontSize: 10);
    final boldStyle = pw.TextStyle(font: fontBold, fontSize: 10);
    final subHeaderStyle = pw.TextStyle(font: fontBold, fontSize: 11);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        build: (pw.Context ctx) {
          return [
            // Header
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: PdfColors.blue50,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                children: [
                  pw.Text(
                    'employees.payslip'.tr(),
                    style: pw.TextStyle(font: fontBold, fontSize: 20),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(periodDisplay, style: subHeaderStyle),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // Employee Info
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('employees.basic_info'.tr(), style: subHeaderStyle),
                  pw.SizedBox(height: 8),
                  _pdfInfoRow('employees.name'.tr(), employee.name, baseStyle),
                  if (employee.position != null)
                    _pdfInfoRow(
                      'employees.position'.tr(),
                      employee.position!,
                      baseStyle,
                    ),
                  if (employee.department != null)
                    _pdfInfoRow(
                      'employees.department'.tr(),
                      employee.department!,
                      baseStyle,
                    ),
                  if (employee.employeeCode != null)
                    _pdfInfoRow(
                      'employees.employee_code'.tr(),
                      employee.employeeCode!,
                      baseStyle,
                    ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // Attendance Summary
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'employees.attendance_summary'.tr(),
                    style: subHeaderStyle,
                  ),
                  pw.SizedBox(height: 8),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                    children: [
                      _pdfStatBox(
                        'employees.status_present'.tr(),
                        presentCount.toString(),
                        PdfColors.green,
                        baseStyle,
                        boldStyle,
                      ),
                      _pdfStatBox(
                        'employees.status_late'.tr(),
                        lateCount.toString(),
                        PdfColors.orange,
                        baseStyle,
                        boldStyle,
                      ),
                      _pdfStatBox(
                        'employees.status_absent'.tr(),
                        absentCount.toString(),
                        PdfColors.red,
                        baseStyle,
                        boldStyle,
                      ),
                      _pdfStatBox(
                        'employees.status_on_leave'.tr(),
                        leaveCount.toString(),
                        PdfColors.blue,
                        baseStyle,
                        boldStyle,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // Leave Summary
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'employees.leave_summary'.tr(),
                    style: subHeaderStyle,
                  ),
                  pw.SizedBox(height: 8),
                  _pdfInfoRow(
                    'employees.leave_status_approved'.tr(),
                    approvedLeaves.toString(),
                    baseStyle,
                  ),
                  _pdfInfoRow(
                    'employees.total_leave_days'.tr(),
                    totalLeaveDays.toString(),
                    baseStyle,
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // Sales Target
            if (salesTargetBonus != null &&
                salesTargetBonus.salesTargetCents > 0) ...[
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(
                    color: salesTargetBonus.achieved
                        ? PdfColors.green300
                        : PdfColors.orange300,
                  ),
                  borderRadius: pw.BorderRadius.circular(6),
                  color: salesTargetBonus.achieved
                      ? PdfColors.green50
                      : PdfColors.orange50,
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      salesTargetBonus.achieved
                          ? 'employees.target_achieved'.tr()
                          : 'employees.target_not_achieved'.tr(),
                      style: subHeaderStyle.copyWith(
                        color: salesTargetBonus.achieved
                            ? PdfColors.green800
                            : PdfColors.orange800,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    _pdfMoneyRow(
                      'employees.sales_target'.tr(),
                      cs.format(salesTargetBonus.salesTargetCents),
                      baseStyle,
                    ),
                    _pdfMoneyRow(
                      'employees.actual_sales'.tr(),
                      cs.format(salesTargetBonus.actualSalesCents),
                      baseStyle,
                    ),
                    if (salesTargetBonus.achieved)
                      _pdfMoneyRow(
                        'employees.target_bonus'.tr(),
                        '+ ${cs.format(salesTargetBonus.targetBonusCents)}',
                        boldStyle,
                        valueColor: PdfColors.green800,
                      ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),
            ],

            // Salary Breakdown
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.blue200),
                borderRadius: pw.BorderRadius.circular(6),
                color: PdfColors.blue50,
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'employees.payslip_summary'.tr(),
                    style: subHeaderStyle,
                  ),
                  pw.SizedBox(height: 8),
                  _pdfMoneyRow(
                    'employees.basic_salary'.tr(),
                    cs.format(calc.basicSalaryCents),
                    baseStyle,
                  ),
                  _pdfMoneyRow(
                    'employees.total_commission'.tr(),
                    cs.format(calc.commissionCents),
                    baseStyle,
                  ),
                  _pdfMoneyRow(
                    'employees.bonus'.tr(),
                    cs.format(calc.bonusCents),
                    baseStyle,
                  ),
                  _pdfMoneyRow(
                    'employees.overtime_pay'.tr(),
                    cs.format(calc.overtimeCents),
                    baseStyle,
                  ),
                  pw.Divider(),
                  _pdfMoneyRow(
                    'employees.gross_pay'.tr(),
                    cs.format(calc.grossPayCents),
                    boldStyle,
                  ),
                  if (calc.absenceDeductionCents > 0)
                    _pdfMoneyRow(
                      'employees.absence_deduction'.tr(),
                      '- ${cs.format(calc.absenceDeductionCents)}',
                      baseStyle,
                      valueColor: PdfColors.red,
                    ),
                  if (calc.lateDeductionCents > 0)
                    _pdfMoneyRow(
                      'employees.late_deduction'.tr(),
                      '- ${cs.format(calc.lateDeductionCents)}',
                      baseStyle,
                      valueColor: PdfColors.orange,
                    ),
                  _pdfMoneyRow(
                    'employees.total_deductions'.tr(),
                    '- ${cs.format(calc.totalDeductionCents)}',
                    boldStyle,
                    valueColor: PdfColors.red,
                  ),
                  pw.Divider(thickness: 2),
                  _pdfMoneyRow(
                    'employees.net_pay'.tr(),
                    cs.format(calc.netPayCents),
                    pw.TextStyle(font: fontBold, fontSize: 14),
                    valueColor: PdfColors.green800,
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 24),

            // Footer
            pw.Container(
              alignment: pw.Alignment.center,
              child: pw.Text(
                '${'employees.generated_on'.tr()}: ${DateFormat('yyyy-MM-dd HH:mm', locale.toString()).format(DateTime.now())}',
                style: pw.TextStyle(
                  font: font,
                  fontSize: 8,
                  color: PdfColors.grey500,
                ),
              ),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _pdfInfoRow(String label, String value, pw.TextStyle style) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: style),
          pw.Text(value, style: style),
        ],
      ),
    );
  }

  static pw.Widget _pdfMoneyRow(
    String label,
    String value,
    pw.TextStyle style, {
    PdfColor? valueColor,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: style),
          pw.Text(
            value,
            style: valueColor != null
                ? style.copyWith(color: valueColor)
                : style,
          ),
        ],
      ),
    );
  }

  static pw.Widget _pdfStatBox(
    String label,
    String value,
    PdfColor color,
    pw.TextStyle baseStyle,
    pw.TextStyle boldStyle,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: color, width: 0.5),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        children: [
          pw.Text(value, style: boldStyle.copyWith(color: color, fontSize: 16)),
          pw.SizedBox(height: 2),
          pw.Text(label, style: baseStyle.copyWith(fontSize: 8)),
        ],
      ),
    );
  }
}
