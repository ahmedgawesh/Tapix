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
import '../../../../core/database/app_database.dart';

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

  /// Print a trial balance report
  static Future<void> printTrialBalance({
    required BuildContext context,
    required List<Account> accounts,
    required DateTime asOfDate,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();

    final pdf = await _buildTrialBalancePdf(
      accounts: accounts,
      asOfDate: asOfDate,
      cs: cs,
      locale: locale,
      isRtl: isRtl,
      company: company,
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'TrialBalance_${DateFormat('yyyyMMdd').format(asOfDate)}',
    );
  }

  /// Share a trial balance report
  static Future<void> shareTrialBalance({
    required BuildContext context,
    required List<Account> accounts,
    required DateTime asOfDate,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();

    final pdf = await _buildTrialBalancePdf(
      accounts: accounts,
      asOfDate: asOfDate,
      cs: cs,
      locale: locale,
      isRtl: isRtl,
      company: company,
    );

    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'TrialBalance_${DateFormat('yyyyMMdd').format(asOfDate)}.pdf',
    );
  }

  /// Print a Profit & Loss report
  static Future<void> printProfitLoss({
    required BuildContext context,
    required List<PnlSection> sections,
    required int totalRevenue,
    required int totalExpenses,
    required int netProfit,
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
              _buildHeader(company, 'accounting.journal_entry'.tr(), fonts, dir),
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
                    '${'accounting.entry_date'.tr()}: ${DateFormat.yMMMd().format(entry.entryDate)}',
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
                    '${'accounting.type'.tr()}: ${'accounting.type_${entry.entryType}'.tr()}',
                    style: pw.TextStyle(font: fonts.regular, fontSize: 10),
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                '${'accounting.description'.tr()}: ${entry.description}',
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
                  final account = accounts.where((a) => a.id == line.accountId).firstOrNull;
                  final debit = line.debitCents.toBigInt().toInt();
                  final credit = line.creditCents.toBigInt().toInt();
                  return [
                    account != null ? '${account.accountCode} - ${account.accountName}' : '?',
                    line.description ?? '',
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
                '${'accounting.printed_on'.tr()}: ${DateFormat.yMMMd().add_jm().format(DateTime.now())}',
                style: pw.TextStyle(font: fonts.regular, fontSize: 8, color: PdfColors.grey600),
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
    required List<Account> accounts,
    required DateTime asOfDate,
    required CurrencyService cs,
    required Locale locale,
    required bool isRtl,
    required CompanyProfile company,
  }) async {
    final fonts = await _loadFonts();
    final pdf = pw.Document();
    final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;

    // Calculate trial balance
    int totalDebits = 0;
    int totalCredits = 0;
    final rows = <List<String>>[];

    for (final account in accounts) {
      final balance = account.balanceCents.toBigInt().toInt();
      if (balance == 0) continue;

      final isDebitNormal = account.accountType == 'asset' || account.accountType == 'expense';
      int debit = 0;
      int credit = 0;

      if (isDebitNormal) {
        if (balance >= 0) {
          debit = balance;
        } else {
          credit = -balance;
        }
      } else {
        if (balance >= 0) {
          credit = balance;
        } else {
          debit = -balance;
        }
      }

      totalDebits += debit;
      totalCredits += credit;

      rows.add([
        account.accountCode,
        account.accountName,
        debit > 0 ? cs.formatCents(debit) : '-',
        credit > 0 ? cs.formatCents(credit) : '-',
      ]);
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        textDirection: dir,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildHeader(company, 'accounting.trial_balance'.tr(), fonts, dir),
              pw.SizedBox(height: 8),
              pw.Text(
                '${'accounting.as_of'.tr()}: ${DateFormat.yMMMd().format(asOfDate)}',
                style: pw.TextStyle(font: fonts.regular, fontSize: 10),
              ),
              pw.SizedBox(height: 16),

              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 9),
                cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 9),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
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
                '${'accounting.printed_on'.tr()}: ${DateFormat.yMMMd().add_jm().format(DateTime.now())}',
                style: pw.TextStyle(font: fonts.regular, fontSize: 8, color: PdfColors.grey600),
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
                '${'accounting.as_of'.tr()}: ${DateFormat.yMMMd().format(asOfDate)}',
                style: pw.TextStyle(font: fonts.regular, fontSize: 10),
              ),
              pw.SizedBox(height: 16),

              // Sections
              ...sections.expand((section) => [
                pw.Text(
                  section.title,
                  style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                ),
                pw.SizedBox(height: 4),
                pw.TableHelper.fromTextArray(
                  headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 9),
                  cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 9),
                  headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
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
                  data: section.items.map((item) => [
                    item.code,
                    item.name,
                    cs.formatCents(item.amountCents),
                  ]).toList(),
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
              ]),

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
                        pw.Text('reports.total_revenue'.tr(),
                            style: pw.TextStyle(font: fonts.regular, fontSize: 10)),
                        pw.Text(cs.formatCents(totalRevenue),
                            style: pw.TextStyle(font: fonts.bold, fontSize: 10)),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('reports.total_expenses'.tr(),
                            style: pw.TextStyle(font: fonts.regular, fontSize: 10)),
                        pw.Text('(${cs.formatCents(totalExpenses)})',
                            style: pw.TextStyle(font: fonts.bold, fontSize: 10)),
                      ],
                    ),
                    pw.Divider(),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          netProfit >= 0 ? 'reports.net_profit'.tr() : 'reports.net_loss'.tr(),
                          style: pw.TextStyle(font: fonts.bold, fontSize: 12),
                        ),
                        pw.Text(
                          cs.formatCents(netProfit.abs()),
                          style: pw.TextStyle(
                            font: fonts.bold,
                            fontSize: 12,
                            color: netProfit >= 0 ? PdfColors.green700 : PdfColors.red700,
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
                '${'accounting.printed_on'.tr()}: ${DateFormat.yMMMd().add_jm().format(DateTime.now())}',
                style: pw.TextStyle(font: fonts.regular, fontSize: 8, color: PdfColors.grey600),
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
                '${'accounting.as_of'.tr()}: ${DateFormat.yMMMd().format(asOfDate)}',
                style: pw.TextStyle(font: fonts.regular, fontSize: 10),
              ),
              pw.SizedBox(height: 16),

              // Sections
              ...sections.expand((section) => [
                pw.Text(
                  section.title,
                  style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                ),
                pw.SizedBox(height: 4),
                pw.TableHelper.fromTextArray(
                  headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 9),
                  cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 9),
                  headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
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
                  data: section.items.map((item) => [
                    item.code,
                    item.name,
                    cs.formatCents(item.amountCents),
                  ]).toList(),
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
              ]),

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
                        pw.Text('reports.total_assets'.tr(),
                            style: pw.TextStyle(font: fonts.bold, fontSize: 11)),
                        pw.Text(cs.formatCents(totalAssets),
                            style: pw.TextStyle(font: fonts.bold, fontSize: 11)),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('reports.total_liabilities_equity'.tr(),
                            style: pw.TextStyle(font: fonts.bold, fontSize: 11)),
                        pw.Text(cs.formatCents(totalLiabilitiesAndEquity),
                            style: pw.TextStyle(font: fonts.bold, fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),

              if (isBalanced)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 8),
                  child: pw.Text(
                    'reports.balance_sheet_balanced'.tr(),
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
                '${'accounting.printed_on'.tr()}: ${DateFormat.yMMMd().add_jm().format(DateTime.now())}',
                style: pw.TextStyle(font: fonts.regular, fontSize: 8, color: PdfColors.grey600),
              ),
            ],
          );
        },
      ),
    );

    return pdf;
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
            style: pw.TextStyle(font: fonts.regular, fontSize: 9, color: PdfColors.grey600),
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
      final regularData = await rootBundle.load('assets/fonts/IBMPlexSansArabic-Regular.ttf');
      final boldData = await rootBundle.load('assets/fonts/IBMPlexSansArabic-Bold.ttf');
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

  const PnlLineItem({required this.code, required this.name, required this.amountCents});
}

class PnlSection {
  final String title;
  final List<PnlLineItem> items;
  final int totalCents;

  const PnlSection({required this.title, required this.items, required this.totalCents});
}

class BalanceSheetLineItem {
  final String code;
  final String name;
  final int amountCents;

  const BalanceSheetLineItem({required this.code, required this.name, required this.amountCents});
}

class BalanceSheetSection {
  final String title;
  final List<BalanceSheetLineItem> items;
  final int totalCents;

  const BalanceSheetSection({required this.title, required this.items, required this.totalCents});
}
