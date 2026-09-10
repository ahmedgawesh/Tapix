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
import '../../../../core/database/app_database.dart';
import '../../domain/models/trial_balance.dart';
import '../../../reports/presentation/bloc/customer_reports_bloc.dart';
import '../../../reports/presentation/bloc/customer_sales_returns_reports_bloc.dart';
import '../../../reports/presentation/widgets/report_date_range.dart';
import '../utils/account_display_name.dart';
import '../utils/journal_description_localizer.dart';
import '../utils/journal_entry_localizer.dart';

class JournalPdfService {
  /// Print a journal entry PDF
  static Future<void> printJournalEntry({
    required BuildContext context,
    required JournalEntry entry,
    required List<JournalEntryLine> lines,
    required List<Account> accounts,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();

    final pdf = await _buildJournalEntryPdf(
      entry: entry,
      lines: lines,
      accounts: accounts,
      cs: cs,
      locale: locale,
      isRtl: isRtl,
      company: company,
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'JournalEntry_${entry.entryNumber}',
    );
  }

  /// Share a journal entry PDF
  static Future<void> shareJournalEntry({
    required BuildContext context,
    required JournalEntry entry,
    required List<JournalEntryLine> lines,
    required List<Account> accounts,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();

    final pdf = await _buildJournalEntryPdf(
      entry: entry,
      lines: lines,
      accounts: accounts,
      cs: cs,
      locale: locale,
      isRtl: isRtl,
      company: company,
    );

    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'JournalEntry_${entry.entryNumber}.pdf',
    );
  }

  /// Print a trial balance report.
  /// The PDF consumes the same posted-journal-derived model shown on screen.
  static Future<void> printTrialBalance({
    required BuildContext context,
    required TrialBalance trialBalance,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();
    final pdf = await _buildTrialBalancePdf(
      trialBalance: trialBalance,
      cs: cs,
      locale: locale,
      isRtl: isRtl,
      company: company,
    );
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name:
          'TrialBalance_${DateFormat('yyyyMMdd').format(trialBalance.asOfDate)}',
    );
  }

  /// Share a trial balance report.
  static Future<void> shareTrialBalance({
    required BuildContext context,
    required TrialBalance trialBalance,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();
    final pdf = await _buildTrialBalancePdf(
      trialBalance: trialBalance,
      cs: cs,
      locale: locale,
      isRtl: isRtl,
      company: company,
    );
    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'TrialBalance_${DateFormat('yyyyMMdd').format(trialBalance.asOfDate)}.pdf',
    );
  }

  /// Print a Profit & Loss report
  static Future<void> printProfitLoss({
    required BuildContext context,
    required List<PnlSection> sections,
    required int totalRevenue,
    required int totalExpenses,
    required int netProfit,
    required DateTime startDate,
    required DateTime asOfDate,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();

    final pdf = await _buildProfitLossPdf(
      sections: sections,
      totalRevenue: totalRevenue,
      totalExpenses: totalExpenses,
      netProfit: netProfit,
      startDate: startDate,
      asOfDate: asOfDate,
      cs: cs,
      locale: locale,
      isRtl: isRtl,
      company: company,
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'ProfitLoss_${DateFormat('yyyyMMdd').format(asOfDate)}',
    );
  }

  /// Share a Profit & Loss report
  static Future<void> shareProfitLoss({
    required BuildContext context,
    required List<PnlSection> sections,
    required int totalRevenue,
    required int totalExpenses,
    required int netProfit,
    required DateTime startDate,
    required DateTime asOfDate,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();

    final pdf = await _buildProfitLossPdf(
      sections: sections,
      totalRevenue: totalRevenue,
      totalExpenses: totalExpenses,
      netProfit: netProfit,
      startDate: startDate,
      asOfDate: asOfDate,
      cs: cs,
      locale: locale,
      isRtl: isRtl,
      company: company,
    );

    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'ProfitLoss_${DateFormat('yyyyMMdd').format(asOfDate)}.pdf',
    );
  }

  /// Print a Balance Sheet report
  static Future<void> printBalanceSheet({
    required BuildContext context,
    required List<BalanceSheetSection> sections,
    required int totalAssets,
    required int totalLiabilitiesAndEquity,
    required bool isBalanced,
    required DateTime asOfDate,
    List<String> diagnosticHints = const [],
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();

    final pdf = await _buildBalanceSheetPdf(
      sections: sections,
      totalAssets: totalAssets,
      totalLiabilitiesAndEquity: totalLiabilitiesAndEquity,
      isBalanced: isBalanced,
      asOfDate: asOfDate,
      cs: cs,
      locale: locale,
      isRtl: isRtl,
      company: company,
      diagnosticHints: diagnosticHints,
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'BalanceSheet_${DateFormat('yyyyMMdd').format(asOfDate)}',
    );
  }

  /// Share a Balance Sheet report
  static Future<void> shareBalanceSheet({
    required BuildContext context,
    required List<BalanceSheetSection> sections,
    required int totalAssets,
    required int totalLiabilitiesAndEquity,
    required bool isBalanced,
    required DateTime asOfDate,
    List<String> diagnosticHints = const [],
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();

    final pdf = await _buildBalanceSheetPdf(
      sections: sections,
      totalAssets: totalAssets,
      totalLiabilitiesAndEquity: totalLiabilitiesAndEquity,
      isBalanced: isBalanced,
      asOfDate: asOfDate,
      cs: cs,
      locale: locale,
      isRtl: isRtl,
      company: company,
      diagnosticHints: diagnosticHints,
    );

    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'BalanceSheet_${DateFormat('yyyyMMdd').format(asOfDate)}.pdf',
    );
  }

  // ═══════════════════════════════════════════════════════
  // JOURNAL ENTRY PDF
  // ═══════════════════════════════════════════════════════

  static Future<pw.Document> _buildJournalEntryPdf({
    required JournalEntry entry,
    required List<JournalEntryLine> lines,
    required List<Account> accounts,
    required CurrencyService cs,
    required Locale locale,
    required bool isRtl,
    required CompanyProfile company,
  }) async {
    final fonts = await _loadFonts();
    final pdf = pw.Document();
    final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        textDirection: dir,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              _buildHeader(
                company,
                'accounting.journal_entry'.tr(),
                fonts,
                dir,
              ),
              pw.SizedBox(height: 20),

              // Entry info
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    '${'accounting.entry_number'.tr()}: ${entry.entryNumber}',
                    style: pw.TextStyle(font: fonts.bold, fontSize: 12),
                  ),
                  pw.Text(
                    '${'accounting.entry_date'.tr()}: '
                    '${DateFormat('dd/MM/yyyy').format(entry.entryDate)}',
                    style: pw.TextStyle(font: fonts.regular, fontSize: 10),
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    '${'accounting.status'.tr()}: ${'accounting.status_${entry.status}'.tr()}',
                    style: pw.TextStyle(font: fonts.regular, fontSize: 10),
                  ),
                  pw.Text(
                    '${'accounting.type'.tr()}: '
                    '${localizedJournalEntryType(entry.entryType)}',
                    style: pw.TextStyle(font: fonts.regular, fontSize: 10),
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                '${'accounting.description'.tr()}: '
                '${localizedJournalDescription(entry.description)}',
                style: pw.TextStyle(font: fonts.regular, fontSize: 10),
              ),
              pw.SizedBox(height: 16),

              // Lines table
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 9),
                cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 9),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey200,
                ),
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerLeft,
                  2: pw.Alignment.centerRight,
                  3: pw.Alignment.centerRight,
                },
                headers: [
                  'accounting.account'.tr(),
                  'accounting.description'.tr(),
                  'accounting.debit'.tr(),
                  'accounting.credit'.tr(),
                ],
                data: lines.map((line) {
                  final account = accounts
                      .where((a) => a.id == line.accountId)
                      .firstOrNull;
                  final debit = line.debitCents.toBigInt().toInt();
                  final credit = line.creditCents.toBigInt().toInt();
                  return [
                    account != null
                        ? '${account.accountCode} - '
                              '${localizedAccountName(account)}'
                        : '?',
                    localizedJournalDescription(line.description),
                    debit > 0 ? cs.formatCents(debit) : '-',
                    credit > 0 ? cs.formatCents(credit) : '-',
                  ];
                }).toList(),
              ),
              pw.SizedBox(height: 12),

              // Totals
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      '${'accounting.total_debits'.tr()}: ${cs.formatCents(entry.totalDebitCents.toBigInt().toInt())}',
                      style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                    ),
                    pw.Text(
                      '${'accounting.total_credits'.tr()}: ${cs.formatCents(entry.totalCreditCents.toBigInt().toInt())}',
                      style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                    ),
                  ],
                ),
              ),

              pw.Spacer(),

              // Footer
              pw.Divider(),
              pw.Text(
                '${'accounting.printed_on'.tr()}: '
                '${DateFormat('dd/MM/yyyy').add_jm().format(DateTime.now())}',
                style: pw.TextStyle(
                  font: fonts.regular,
                  fontSize: 8,
                  color: PdfColors.grey600,
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf;
  }

  // ═══════════════════════════════════════════════════════
  // TRIAL BALANCE PDF
  // ═══════════════════════════════════════════════════════

  static Future<pw.Document> _buildTrialBalancePdf({
    required TrialBalance trialBalance,
    required CurrencyService cs,
    required Locale locale,
    required bool isRtl,
    required CompanyProfile company,
  }) async {
    final fonts = await _loadFonts();
    final pdf = pw.Document();
    final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;

    final rows = trialBalance.nonZeroItems
        .map(
          (item) => [
            item.accountCode,
            item.accountName,
            item.debitCents > 0 ? cs.formatCents(item.debitCents) : '-',
            item.creditCents > 0 ? cs.formatCents(item.creditCents) : '-',
          ],
        )
        .toList(growable: false);
    final totalDebits = trialBalance.totalDebitCents;
    final totalCredits = trialBalance.totalCreditCents;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        textDirection: dir,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildHeader(
                company,
                'accounting.trial_balance'.tr(),
                fonts,
                dir,
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                '${'accounting.as_of'.tr()}: ${DateFormat('dd/MM/yyyy').format(trialBalance.asOfDate)}',
                style: pw.TextStyle(font: fonts.regular, fontSize: 10),
              ),
              pw.SizedBox(height: 16),

              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 9),
                cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 9),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey200,
                ),
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerLeft,
                  2: pw.Alignment.centerRight,
                  3: pw.Alignment.centerRight,
                },
                headers: [
                  'accounting.code'.tr(),
                  'accounting.account'.tr(),
                  'accounting.debit'.tr(),
                  'accounting.credit'.tr(),
                ],
                data: rows,
              ),
              pw.SizedBox(height: 12),

              // Totals
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      '${'accounting.total_debits'.tr()}: ${cs.formatCents(totalDebits)}',
                      style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                    ),
                    pw.Text(
                      '${'accounting.total_credits'.tr()}: ${cs.formatCents(totalCredits)}',
                      style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                    ),
                  ],
                ),
              ),

              if (totalDebits == totalCredits)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 8),
                  child: pw.Text(
                    'accounting.trial_balance_balanced'.tr(),
                    style: pw.TextStyle(
                      font: fonts.bold,
                      fontSize: 10,
                      color: PdfColors.green700,
                    ),
                  ),
                ),

              pw.Spacer(),
              pw.Divider(),
              pw.Text(
                '${'accounting.printed_on'.tr()}: ${DateFormat('dd/MM/yyyy').add_jm().format(DateTime.now())}',
                style: pw.TextStyle(
                  font: fonts.regular,
                  fontSize: 8,
                  color: PdfColors.grey600,
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf;
  }

  // ═══════════════════════════════════════════════════════
  // PROFIT & LOSS PDF
  // ═══════════════════════════════════════════════════════

  static Future<pw.Document> _buildProfitLossPdf({
    required List<PnlSection> sections,
    required int totalRevenue,
    required int totalExpenses,
    required int netProfit,
    required DateTime startDate,
    required DateTime asOfDate,
    required CurrencyService cs,
    required Locale locale,
    required bool isRtl,
    required CompanyProfile company,
  }) async {
    final fonts = await _loadFonts();
    final pdf = pw.Document();
    final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        textDirection: dir,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildHeader(company, 'reports.profit_loss'.tr(), fonts, dir),
              pw.SizedBox(height: 8),
              pw.Text(
                '${DateFormat('dd/MM/yyyy').format(startDate)} – '
                '${DateFormat('dd/MM/yyyy').format(asOfDate)}',
                style: pw.TextStyle(font: fonts.regular, fontSize: 10),
              ),
              pw.SizedBox(height: 16),

              // Sections
              ...sections.expand(
                (section) => [
                  pw.Text(
                    section.title,
                    style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                  ),
                  pw.SizedBox(height: 4),
                  pw.TableHelper.fromTextArray(
                    headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 9),
                    cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 9),
                    headerDecoration: const pw.BoxDecoration(
                      color: PdfColors.grey200,
                    ),
                    cellAlignments: {
                      0: pw.Alignment.centerLeft,
                      1: pw.Alignment.centerLeft,
                      2: pw.Alignment.centerRight,
                    },
                    headers: [
                      'accounting.code'.tr(),
                      'accounting.account'.tr(),
                      'reports.balance'.tr(),
                    ],
                    data: section.items
                        .map(
                          (item) => [
                            item.code,
                            item.name,
                            cs.formatCents(item.amountCents),
                          ],
                        )
                        .toList(),
                  ),
                  pw.Container(
                    alignment: pw.Alignment.centerRight,
                    padding: const pw.EdgeInsets.symmetric(vertical: 4),
                    child: pw.Text(
                      '${section.title}: ${cs.formatCents(section.totalCents)}',
                      style: pw.TextStyle(font: fonts.bold, fontSize: 10),
                    ),
                  ),
                  pw.SizedBox(height: 12),
                ],
              ),

              // Summary
              pw.Divider(),
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                ),
                child: pw.Column(
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'reports.total_revenue'.tr(),
                          style: pw.TextStyle(
                            font: fonts.regular,
                            fontSize: 10,
                          ),
                        ),
                        pw.Text(
                          cs.formatCents(totalRevenue),
                          style: pw.TextStyle(font: fonts.bold, fontSize: 10),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'reports.total_expenses'.tr(),
                          style: pw.TextStyle(
                            font: fonts.regular,
                            fontSize: 10,
                          ),
                        ),
                        pw.Text(
                          '(${cs.formatCents(totalExpenses)})',
                          style: pw.TextStyle(font: fonts.bold, fontSize: 10),
                        ),
                      ],
                    ),
                    pw.Divider(),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          netProfit >= 0
                              ? 'reports.net_profit'.tr()
                              : 'reports.net_loss'.tr(),
                          style: pw.TextStyle(font: fonts.bold, fontSize: 12),
                        ),
                        pw.Text(
                          cs.formatCents(netProfit.abs()),
                          style: pw.TextStyle(
                            font: fonts.bold,
                            fontSize: 12,
                            color: netProfit >= 0
                                ? PdfColors.green700
                                : PdfColors.red700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              pw.Spacer(),
              pw.Divider(),
              pw.Text(
                '${'accounting.printed_on'.tr()}: ${DateFormat('dd/MM/yyyy').add_jm().format(DateTime.now())}',
                style: pw.TextStyle(
                  font: fonts.regular,
                  fontSize: 8,
                  color: PdfColors.grey600,
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf;
  }

  // ═══════════════════════════════════════════════════════
  // BALANCE SHEET PDF
  // ═══════════════════════════════════════════════════════

  static Future<pw.Document> _buildBalanceSheetPdf({
    required List<BalanceSheetSection> sections,
    required int totalAssets,
    required int totalLiabilitiesAndEquity,
    required bool isBalanced,
    required DateTime asOfDate,
    required CurrencyService cs,
    required Locale locale,
    required bool isRtl,
    required CompanyProfile company,
    List<String> diagnosticHints = const [],
  }) async {
    final fonts = await _loadFonts();
    final pdf = pw.Document();
    final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        textDirection: dir,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildHeader(company, 'reports.balance_sheet'.tr(), fonts, dir),
              pw.SizedBox(height: 8),
              pw.Text(
                '${'accounting.as_of'.tr()}: ${DateFormat('dd/MM/yyyy').format(asOfDate)}',
                style: pw.TextStyle(font: fonts.regular, fontSize: 10),
              ),
              pw.SizedBox(height: 16),

              // Sections
              ...sections.expand(
                (section) => [
                  pw.Text(
                    section.title,
                    style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                  ),
                  pw.SizedBox(height: 4),
                  pw.TableHelper.fromTextArray(
                    headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 9),
                    cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 9),
                    headerDecoration: const pw.BoxDecoration(
                      color: PdfColors.grey200,
                    ),
                    cellAlignments: {
                      0: pw.Alignment.centerLeft,
                      1: pw.Alignment.centerLeft,
                      2: pw.Alignment.centerRight,
                    },
                    headers: [
                      'accounting.code'.tr(),
                      'accounting.account'.tr(),
                      'reports.balance'.tr(),
                    ],
                    data: section.items
                        .map(
                          (item) => [
                            item.code,
                            item.name,
                            cs.formatCents(item.amountCents),
                          ],
                        )
                        .toList(),
                  ),
                  pw.Container(
                    alignment: pw.Alignment.centerRight,
                    padding: const pw.EdgeInsets.symmetric(vertical: 4),
                    child: pw.Text(
                      '${section.title}: ${cs.formatCents(section.totalCents)}',
                      style: pw.TextStyle(font: fonts.bold, fontSize: 10),
                    ),
                  ),
                  pw.SizedBox(height: 12),
                ],
              ),

              // Summary
              pw.Divider(),
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                ),
                child: pw.Column(
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'reports.total_assets'.tr(),
                          style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                        ),
                        pw.Text(
                          cs.formatCents(totalAssets),
                          style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'reports.total_liabilities_equity'.tr(),
                          style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                        ),
                        pw.Text(
                          cs.formatCents(totalLiabilitiesAndEquity),
                          style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Balance status
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 8),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      isBalanced
                          ? 'reports.balance_sheet_balanced'.tr()
                          : 'reports.balance_sheet_unbalanced'.tr(),
                      style: pw.TextStyle(
                        font: fonts.bold,
                        fontSize: 10,
                        color: isBalanced ? PdfColors.green700 : PdfColors.red,
                      ),
                    ),
                    if (!isBalanced)
                      pw.Text(
                        'reports.balance_sheet_difference'.tr(
                          args: [
                            cs.formatCents(
                              (totalAssets - totalLiabilitiesAndEquity).abs(),
                            ),
                          ],
                        ),
                        style: pw.TextStyle(
                          font: fonts.regular,
                          fontSize: 9,
                          color: PdfColors.red,
                        ),
                      ),
                  ],
                ),
              ),

              // Diagnostic hints (when unbalanced)
              if (!isBalanced && diagnosticHints.isNotEmpty) ...[
                pw.SizedBox(height: 8),
                pw.Container(
                  padding: const pw.EdgeInsets.all(6),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.orange),
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(4),
                    ),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'reports.diag_panel_title'.tr(),
                        style: pw.TextStyle(
                          font: fonts.bold,
                          fontSize: 9,
                          color: PdfColors.orange,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      ...diagnosticHints.map(
                        (hint) => pw.Padding(
                          padding: const pw.EdgeInsets.only(bottom: 2),
                          child: pw.Row(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                '• ',
                                style: pw.TextStyle(
                                  font: fonts.regular,
                                  fontSize: 8,
                                ),
                              ),
                              pw.Expanded(
                                child: pw.Text(
                                  hint,
                                  style: pw.TextStyle(
                                    font: fonts.regular,
                                    fontSize: 8,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              pw.Spacer(),
              pw.Divider(),
              pw.Text(
                '${'accounting.printed_on'.tr()}: ${DateFormat('dd/MM/yyyy').add_jm().format(DateTime.now())}',
                style: pw.TextStyle(
                  font: fonts.regular,
                  fontSize: 8,
                  color: PdfColors.grey600,
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf;
  }

  // ═══════════════════════════════════════════════════════
  // CUSTOMER REPORTS PDF
  // ═══════════════════════════════════════════════════════

  /// Print a Customer Report PDF
  /// NOTE: Use CustomerReportPdfService for new customer report PDF generation.
  /// This legacy method is retained for backward compatibility.
  static Future<void> printCustomerReport({
    required BuildContext context,
    required List<CustomerBalanceItem> customers,
    required List<CustomerAgingItem> agingItems,
    required List<CustomerAnalyticsItem> analyticsItems,
    required int totalReceivablesCents,
    required int totalOverdueCents,
    required ReportDateRange dateRange,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();

    final pdf = await _buildCustomerReportPdf(
      customers: customers,
      agingItems: agingItems,
      analyticsItems: analyticsItems,
      totalReceivablesCents: totalReceivablesCents,
      totalOverdueCents: totalOverdueCents,
      dateRange: dateRange,
      cs: cs,
      locale: locale,
      isRtl: isRtl,
      company: company,
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name:
          'CustomerReport_${DateFormat('yyyyMMdd').format(dateRange.endDate)}',
    );
  }

  /// Share a Customer Report PDF
  /// NOTE: Use CustomerReportPdfService for new customer report PDF generation.
  static Future<void> shareCustomerReport({
    required BuildContext context,
    required List<CustomerBalanceItem> customers,
    required List<CustomerAgingItem> agingItems,
    required List<CustomerAnalyticsItem> analyticsItems,
    required int totalReceivablesCents,
    required int totalOverdueCents,
    required ReportDateRange dateRange,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();

    final pdf = await _buildCustomerReportPdf(
      customers: customers,
      agingItems: agingItems,
      analyticsItems: analyticsItems,
      totalReceivablesCents: totalReceivablesCents,
      totalOverdueCents: totalOverdueCents,
      dateRange: dateRange,
      cs: cs,
      locale: locale,
      isRtl: isRtl,
      company: company,
    );

    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'CustomerReport_${DateFormat('yyyyMMdd').format(dateRange.endDate)}.pdf',
    );
  }

  static Future<pw.Document> _buildCustomerReportPdf({
    required List<CustomerBalanceItem> customers,
    required List<CustomerAgingItem> agingItems,
    required List<CustomerAnalyticsItem> analyticsItems,
    required int totalReceivablesCents,
    required int totalOverdueCents,
    required ReportDateRange dateRange,
    required CurrencyService cs,
    required Locale locale,
    required bool isRtl,
    required CompanyProfile company,
  }) async {
    final fonts = await _loadFonts();
    final pdf = pw.Document();
    final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;

    // Page 1: Aging Report
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        textDirection: dir,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildHeader(company, 'reports.customer_aging'.tr(), fonts, dir),
              pw.SizedBox(height: 8),
              pw.Text(
                '${DateFormat('dd/MM/yyyy').format(dateRange.startDate)} — ${DateFormat('dd/MM/yyyy').format(dateRange.endDate)}',
                style: pw.TextStyle(font: fonts.regular, fontSize: 10),
              ),
              pw.SizedBox(height: 8),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    '${'reports.total_receivables'.tr()}: ${cs.formatCents(totalReceivablesCents)}',
                    style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                  ),
                  pw.Text(
                    '${'reports.total_overdue'.tr()}: ${cs.formatCents(totalOverdueCents)}',
                    style: pw.TextStyle(
                      font: fonts.bold,
                      fontSize: 11,
                      color: PdfColors.red700,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 16),

              if (agingItems.isNotEmpty)
                pw.TableHelper.fromTextArray(
                  headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 8),
                  cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 8),
                  headerDecoration: const pw.BoxDecoration(
                    color: PdfColors.grey200,
                  ),
                  cellAlignments: {
                    0: pw.Alignment.centerLeft,
                    1: pw.Alignment.centerRight,
                    2: pw.Alignment.centerRight,
                    3: pw.Alignment.centerRight,
                    4: pw.Alignment.centerRight,
                    5: pw.Alignment.centerRight,
                    6: pw.Alignment.centerRight,
                  },
                  headers: [
                    'reports.customer'.tr(),
                    'reports.aging_current'.tr(),
                    'reports.aging_30'.tr(),
                    'reports.aging_60'.tr(),
                    'reports.aging_90'.tr(),
                    'reports.aging_over_90'.tr(),
                    'reports.aging_total'.tr(),
                  ],
                  data: agingItems
                      .map(
                        (item) => [
                          item.customerName,
                          item.currentCents > 0
                              ? cs.formatCents(item.currentCents)
                              : '-',
                          item.days30Cents > 0
                              ? cs.formatCents(item.days30Cents)
                              : '-',
                          item.days60Cents > 0
                              ? cs.formatCents(item.days60Cents)
                              : '-',
                          item.days90Cents > 0
                              ? cs.formatCents(item.days90Cents)
                              : '-',
                          item.over90Cents > 0
                              ? cs.formatCents(item.over90Cents)
                              : '-',
                          cs.formatCents(item.totalCents),
                        ],
                      )
                      .toList(),
                ),

              pw.Spacer(),
              pw.Divider(),
              pw.Text(
                '${'accounting.printed_on'.tr()}: ${DateFormat('dd/MM/yyyy').add_jm().format(DateTime.now())}',
                style: pw.TextStyle(
                  font: fonts.regular,
                  fontSize: 8,
                  color: PdfColors.grey600,
                ),
              ),
            ],
          );
        },
      ),
    );

    // Page 2+: Per-customer balance breakdown
    for (final customer in customers) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          textDirection: dir,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _buildHeader(
                  company,
                  'reports.customer_statement'.tr(),
                  fonts,
                  dir,
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  customer.customerName,
                  style: pw.TextStyle(font: fonts.bold, fontSize: 12),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  '${DateFormat('dd/MM/yyyy').format(dateRange.startDate)} — ${DateFormat('dd/MM/yyyy').format(dateRange.endDate)}',
                  style: pw.TextStyle(font: fonts.regular, fontSize: 10),
                ),
                pw.SizedBox(height: 8),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      '${'reports.opening_balance'.tr()}: ${cs.formatCents(customer.openingBalanceCents)}',
                      style: pw.TextStyle(font: fonts.regular, fontSize: 10),
                    ),
                    pw.Text(
                      '${'reports.current_balance'.tr()}: ${cs.formatCents(customer.currentBalanceCents)}',
                      style: pw.TextStyle(font: fonts.bold, fontSize: 10),
                    ),
                  ],
                ),
                pw.SizedBox(height: 12),

                pw.TableHelper.fromTextArray(
                  headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 9),
                  cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 9),
                  headerDecoration: const pw.BoxDecoration(
                    color: PdfColors.grey200,
                  ),
                  cellAlignments: {
                    0: pw.Alignment.centerLeft,
                    1: pw.Alignment.centerRight,
                  },
                  headers: ['reports.type'.tr(), 'reports.amount'.tr()],
                  data: [
                    [
                      'reports.total_sales'.tr(),
                      cs.formatCents(customer.totalSalesCents),
                    ],
                    [
                      'reports.total_payments'.tr(),
                      cs.formatCents(customer.totalPaymentsCents),
                    ],
                    [
                      'reports.total_discounts'.tr(),
                      cs.formatCents(customer.totalDiscountsCents),
                    ],
                    [
                      'reports.total_returns'.tr(),
                      cs.formatCents(customer.totalReturnsCents),
                    ],
                  ],
                ),
                pw.SizedBox(height: 12),

                pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        '${'reports.total_sales'.tr()}: ${cs.formatCents(customer.totalSalesCents)}',
                        style: pw.TextStyle(font: fonts.bold, fontSize: 10),
                      ),
                      pw.Text(
                        '${'reports.current_balance'.tr()}: ${cs.formatCents(customer.currentBalanceCents)}',
                        style: pw.TextStyle(font: fonts.bold, fontSize: 10),
                      ),
                    ],
                  ),
                ),

                pw.Spacer(),
                pw.Divider(),
                pw.Text(
                  '${'accounting.printed_on'.tr()}: ${DateFormat('dd/MM/yyyy').add_jm().format(DateTime.now())}',
                  style: pw.TextStyle(
                    font: fonts.regular,
                    fontSize: 8,
                    color: PdfColors.grey600,
                  ),
                ),
              ],
            );
          },
        ),
      );
    }

    return pdf;
  }

  // ═══════════════════════════════════════════════════════
  // CUSTOMER RETURNS REPORTS PDF
  // ═══════════════════════════════════════════════════════

  /// Print a Customer Returns Report PDF
  static Future<void> printCustomerReturnsReport({
    required BuildContext context,
    required List<CustomerReturnSummary> customerSummaries,
    required List<ReturnDetailItem> returnDetails,
    required List<ReturnReasonBreakdown> reasonBreakdown,
    required List<ReturnedProductItem> returnedProducts,
    required int totalReturnsCents,
    required int totalReturnCount,
    required ReportDateRange dateRange,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();

    final pdf = await _buildCustomerReturnsReportPdf(
      customerSummaries: customerSummaries,
      returnDetails: returnDetails,
      reasonBreakdown: reasonBreakdown,
      returnedProducts: returnedProducts,
      totalReturnsCents: totalReturnsCents,
      totalReturnCount: totalReturnCount,
      dateRange: dateRange,
      cs: cs,
      locale: locale,
      isRtl: isRtl,
      company: company,
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name:
          'CustomerReturnsReport_${DateFormat('yyyyMMdd').format(dateRange.endDate)}',
    );
  }

  /// Share a Customer Returns Report PDF
  static Future<void> shareCustomerReturnsReport({
    required BuildContext context,
    required List<CustomerReturnSummary> customerSummaries,
    required List<ReturnDetailItem> returnDetails,
    required List<ReturnReasonBreakdown> reasonBreakdown,
    required List<ReturnedProductItem> returnedProducts,
    required int totalReturnsCents,
    required int totalReturnCount,
    required ReportDateRange dateRange,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();

    final pdf = await _buildCustomerReturnsReportPdf(
      customerSummaries: customerSummaries,
      returnDetails: returnDetails,
      reasonBreakdown: reasonBreakdown,
      returnedProducts: returnedProducts,
      totalReturnsCents: totalReturnsCents,
      totalReturnCount: totalReturnCount,
      dateRange: dateRange,
      cs: cs,
      locale: locale,
      isRtl: isRtl,
      company: company,
    );

    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'CustomerReturnsReport_${DateFormat('yyyyMMdd').format(dateRange.endDate)}.pdf',
    );
  }

  static Future<pw.Document> _buildCustomerReturnsReportPdf({
    required List<CustomerReturnSummary> customerSummaries,
    required List<ReturnDetailItem> returnDetails,
    required List<ReturnReasonBreakdown> reasonBreakdown,
    required List<ReturnedProductItem> returnedProducts,
    required int totalReturnsCents,
    required int totalReturnCount,
    required ReportDateRange dateRange,
    required CurrencyService cs,
    required Locale locale,
    required bool isRtl,
    required CompanyProfile company,
  }) async {
    final fonts = await _loadFonts();
    final pdf = pw.Document();
    final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;

    // Page 1+: Customer Returns Summary + Returned Items Detail
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: dir,
        header: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildHeader(
                company,
                'reports.customer_returns'.tr(),
                fonts,
                dir,
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                '${DateFormat('dd/MM/yyyy').format(dateRange.startDate)} — ${DateFormat('dd/MM/yyyy').format(dateRange.endDate)}',
                style: pw.TextStyle(font: fonts.regular, fontSize: 10),
              ),
              pw.SizedBox(height: 8),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    '${'reports.total_returns_value'.tr()}: ${cs.formatCents(totalReturnsCents)}',
                    style: pw.TextStyle(
                      font: fonts.bold,
                      fontSize: 11,
                      color: PdfColors.red700,
                    ),
                  ),
                  pw.Text(
                    '${'reports.total_return_count'.tr()}: $totalReturnCount',
                    style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
            ],
          );
        },
        footer: (pw.Context context) {
          return pw.Column(
            children: [
              pw.Divider(),
              pw.Text(
                '${'accounting.printed_on'.tr()}: ${DateFormat('dd/MM/yyyy').add_jm().format(DateTime.now())}',
                style: pw.TextStyle(
                  font: fonts.regular,
                  fontSize: 8,
                  color: PdfColors.grey600,
                ),
              ),
            ],
          );
        },
        build: (pw.Context context) {
          return [
            if (customerSummaries.isNotEmpty)
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 8),
                cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 8),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey200,
                ),
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerRight,
                  2: pw.Alignment.centerRight,
                  3: pw.Alignment.centerRight,
                  4: pw.Alignment.centerRight,
                  5: pw.Alignment.centerLeft,
                },
                headers: [
                  'reports.customer'.tr(),
                  'reports.return_count_short'.tr(),
                  'reports.items_returned'.tr(),
                  'reports.total_returned'.tr(),
                  'reports.avg_return'.tr(),
                  'reports.last_return'.tr(),
                ],
                data: customerSummaries
                    .map(
                      (item) => [
                        item.customerName,
                        item.returnCount.toString(),
                        item.totalItemsReturned.toString(),
                        cs.formatCents(item.totalReturnedCents),
                        cs.formatCents(item.averageReturnCents),
                        item.lastReturnDate != null
                            ? DateFormat(
                                'dd/MM/yyyy',
                              ).format(item.lastReturnDate!)
                            : '-',
                      ],
                    )
                    .toList(),
              ),

            // Returned Items Detail (product-level)
            if (returnedProducts.isNotEmpty) ...[
              pw.SizedBox(height: 20),
              pw.Text(
                'reports.returned_items_detail'.tr(),
                style: pw.TextStyle(font: fonts.bold, fontSize: 12),
              ),
              pw.SizedBox(height: 8),
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 8),
                cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 8),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey200,
                ),
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerLeft,
                  2: pw.Alignment.centerLeft,
                  3: pw.Alignment.centerLeft,
                  4: pw.Alignment.centerRight,
                  5: pw.Alignment.centerRight,
                  6: pw.Alignment.centerLeft,
                },
                headers: [
                  'reports.product_name'.tr(),
                  'reports.sku'.tr(),
                  'reports.color'.tr(),
                  'reports.size'.tr(),
                  'reports.quantity'.tr(),
                  'reports.refund_amount'.tr(),
                  'reports.reason'.tr(),
                ],
                data: returnedProducts.map((item) {
                  return [
                    item.productName,
                    item.sku ?? '-',
                    item.colorName ?? '-',
                    item.sizeName ?? '-',
                    localizedQuantity(item.quantity, item.measurementType),
                    cs.formatCents(item.refundCents),
                    item.reason != null ? _pdfReasonLabel(item.reason!) : '-',
                  ];
                }).toList(),
              ),
            ],
          ];
        },
      ),
    );

    // Page 2: Return Reason Breakdown
    if (reasonBreakdown.isNotEmpty) {
      int grandTotalCount = 0;
      for (final r in reasonBreakdown) {
        grandTotalCount += r.count;
      }

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          textDirection: dir,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _buildHeader(
                  company,
                  'reports.return_reason_breakdown'.tr(),
                  fonts,
                  dir,
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  '${DateFormat('dd/MM/yyyy').format(dateRange.startDate)} — ${DateFormat('dd/MM/yyyy').format(dateRange.endDate)}',
                  style: pw.TextStyle(font: fonts.regular, fontSize: 10),
                ),
                pw.SizedBox(height: 16),

                pw.TableHelper.fromTextArray(
                  headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 9),
                  cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 9),
                  headerDecoration: const pw.BoxDecoration(
                    color: PdfColors.grey200,
                  ),
                  cellAlignments: {
                    0: pw.Alignment.centerLeft,
                    1: pw.Alignment.centerRight,
                    2: pw.Alignment.centerRight,
                    3: pw.Alignment.centerRight,
                  },
                  headers: [
                    'reports.reason'.tr(),
                    'reports.return_count_short'.tr(),
                    'reports.percentage'.tr(),
                    'reports.total_returned'.tr(),
                  ],
                  data: reasonBreakdown.map((r) {
                    final pct = grandTotalCount > 0
                        ? (r.count / grandTotalCount * 100)
                        : 0.0;
                    return [
                      _pdfReasonLabel(r.reason),
                      r.count.toString(),
                      '${pct.toStringAsFixed(1)}%',
                      cs.formatCents(r.totalCents),
                    ];
                  }).toList(),
                ),

                pw.Spacer(),
                pw.Divider(),
                pw.Text(
                  '${'accounting.printed_on'.tr()}: ${DateFormat('dd/MM/yyyy').add_jm().format(DateTime.now())}',
                  style: pw.TextStyle(
                    font: fonts.regular,
                    fontSize: 8,
                    color: PdfColors.grey600,
                  ),
                ),
              ],
            );
          },
        ),
      );
    }

    // Page 3+: Return Details
    if (returnDetails.isNotEmpty) {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          textDirection: dir,
          header: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _buildHeader(
                  company,
                  'reports.return_details'.tr(),
                  fonts,
                  dir,
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  '${DateFormat('dd/MM/yyyy').format(dateRange.startDate)} — ${DateFormat('dd/MM/yyyy').format(dateRange.endDate)}',
                  style: pw.TextStyle(font: fonts.regular, fontSize: 10),
                ),
                pw.SizedBox(height: 12),
              ],
            );
          },
          footer: (pw.Context context) {
            return pw.Column(
              children: [
                pw.Divider(),
                pw.Text(
                  '${'accounting.printed_on'.tr()}: ${DateFormat('dd/MM/yyyy').add_jm().format(DateTime.now())}',
                  style: pw.TextStyle(
                    font: fonts.regular,
                    fontSize: 8,
                    color: PdfColors.grey600,
                  ),
                ),
              ],
            );
          },
          build: (pw.Context context) {
            return [
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 8),
                cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 8),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey200,
                ),
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerLeft,
                  2: pw.Alignment.centerLeft,
                  3: pw.Alignment.centerLeft,
                  4: pw.Alignment.centerRight,
                  5: pw.Alignment.centerRight,
                },
                headers: [
                  'reports.return_number'.tr(),
                  'reports.return_date_label'.tr(),
                  'reports.original_invoice'.tr(),
                  'reports.reason'.tr(),
                  'reports.items_returned'.tr(),
                  'reports.total_returned'.tr(),
                ],
                data: returnDetails
                    .map(
                      (item) => [
                        item.returnNumber,
                        DateFormat('dd/MM/yyyy').format(item.returnDate),
                        item.originalInvoiceNumber ?? '-',
                        item.reason ?? '-',
                        item.itemCount.toString(),
                        cs.formatCents(item.totalCents),
                      ],
                    )
                    .toList(),
              ),
            ];
          },
        ),
      );
    }

    return pdf;
  }

  static String _pdfReasonLabel(String reason) {
    switch (reason) {
      case 'wrong_size':
        return 'reports.reason_wrong_size'.tr();
      case 'defective':
        return 'reports.reason_defective'.tr();
      case 'wrong_item':
        return 'reports.reason_wrong_item'.tr();
      case 'changed_mind':
        return 'reports.reason_changed_mind'.tr();
      case 'other':
        return 'reports.reason_other'.tr();
      default:
        return reason;
    }
  }

  // ═══════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════

  static pw.Widget _buildHeader(
    CompanyProfile company,
    String title,
    _PdfFonts fonts,
    pw.TextDirection dir,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          company.name,
          style: pw.TextStyle(font: fonts.bold, fontSize: 16),
        ),
        if (company.address != null && company.address!.isNotEmpty)
          pw.Text(
            company.address!,
            style: pw.TextStyle(
              font: fonts.regular,
              fontSize: 9,
              color: PdfColors.grey600,
            ),
          ),
        pw.SizedBox(height: 8),
        pw.Divider(),
        pw.SizedBox(height: 4),
        pw.Center(
          child: pw.Text(
            title,
            style: pw.TextStyle(font: fonts.bold, fontSize: 14),
          ),
        ),
      ],
    );
  }

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
}

class _PdfFonts {
  final pw.Font regular;
  final pw.Font bold;

  _PdfFonts({required this.regular, required this.bold});
}

// ═══════════════════════════════════════════════════════
// P&L / BALANCE SHEET DATA MODELS
// ═══════════════════════════════════════════════════════

class PnlLineItem {
  final String code;
  final String name;
  final int amountCents;

  const PnlLineItem({
    required this.code,
    required this.name,
    required this.amountCents,
  });
}

class PnlSection {
  final String title;
  final List<PnlLineItem> items;
  final int totalCents;

  const PnlSection({
    required this.title,
    required this.items,
    required this.totalCents,
  });
}

class BalanceSheetLineItem {
  final String code;
  final String name;
  final int amountCents;

  const BalanceSheetLineItem({
    required this.code,
    required this.name,
    required this.amountCents,
  });
}

class BalanceSheetSection {
  final String title;
  final List<BalanceSheetLineItem> items;
  final int totalCents;

  const BalanceSheetSection({
    required this.title,
    required this.items,
    required this.totalCents,
  });
}
