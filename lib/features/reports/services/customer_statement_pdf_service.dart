import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/di/injection_container.dart';
import '../../../core/services/currency_service.dart';
import '../../settings/data/services/company_profile_service.dart';
import '../../settings/domain/entities/company_profile.dart';
import '../presentation/bloc/customer_statement_report_bloc.dart';

class CustomerStatementPdfService {
  static Future<void> printCustomerStatement({
    required BuildContext context,
    required CustomerStatementData data,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();

    final pdf = await _buildPdf(
      data: data,
      cs: cs,
      locale: locale,
      isRtl: isRtl,
      company: company,
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name:
          'CustomerStatement_${data.customerName ?? ''}_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  static Future<void> shareCustomerStatement({
    required BuildContext context,
    required CustomerStatementData data,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();

    final pdf = await _buildPdf(
      data: data,
      cs: cs,
      locale: locale,
      isRtl: isRtl,
      company: company,
    );

    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'CustomerStatement_${data.customerName ?? ''}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  static Future<pw.Document> _buildPdf({
    required CustomerStatementData data,
    required CurrencyService cs,
    required Locale locale,
    required bool isRtl,
    required CompanyProfile company,
  }) async {
    final fonts = await _loadFonts();
    final pdf = pw.Document();
    final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    final lang = locale.languageCode;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: dir,
        build: (pw.Context context) {
          return [
            // Header
            _buildHeader(
                company, _t('customer_statement', lang), fonts, dir),
            pw.SizedBox(height: 8),

            // Period
            pw.Text(
              '${_t('period', lang)}: ${DateFormat.yMMMd().format(data.dateRange.startDate)} — ${DateFormat.yMMMd().format(data.dateRange.endDate)}',
              style: pw.TextStyle(font: fonts.regular, fontSize: 10),
            ),
            pw.SizedBox(height: 12),

            // Customer info
            _buildCustomerInfo(data, fonts, lang),
            pw.SizedBox(height: 12),

            // Balance summary
            _buildBalanceSummary(data, cs, fonts, lang),
            pw.SizedBox(height: 12),

            // Transaction table
            if (data.transactions.isNotEmpty) ...[
              pw.Text(
                _t('transactions', lang),
                style: pw.TextStyle(font: fonts.bold, fontSize: 12),
              ),
              pw.SizedBox(height: 6),
              _buildTransactionTable(data, cs, fonts, lang),
              pw.SizedBox(height: 8),

              // Closing balance footer
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  color: PdfColors.grey100,
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      '${_t('closing_balance', lang)}:',
                      style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                    ),
                    pw.Text(
                      cs.formatCents(data.closingBalanceCents),
                      style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ] else
              pw.Text(
                _t('no_transactions', lang),
                style: pw.TextStyle(
                    font: fonts.regular,
                    fontSize: 10,
                    color: PdfColors.grey600),
              ),

            pw.SizedBox(height: 16),
            pw.Divider(),
            pw.Text(
              '${_t('printed_on', lang)}: ${DateFormat.yMMMd().add_jm().format(DateTime.now())}',
              style: pw.TextStyle(
                  font: fonts.regular,
                  fontSize: 8,
                  color: PdfColors.grey600),
            ),
          ];
        },
      ),
    );

    return pdf;
  }

  static pw.Widget _buildCustomerInfo(
    CustomerStatementData data,
    _PdfFonts fonts,
    String lang,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '${_t('customer', lang)}: ${data.customerName ?? '-'}',
            style: pw.TextStyle(font: fonts.bold, fontSize: 11),
          ),
          if (data.customerPhone != null && data.customerPhone!.isNotEmpty)
            pw.Text(
              '${_t('phone', lang)}: ${data.customerPhone}',
              style: pw.TextStyle(font: fonts.regular, fontSize: 9),
            ),
          if (data.customerEmail != null && data.customerEmail!.isNotEmpty)
            pw.Text(
              '${_t('email', lang)}: ${data.customerEmail}',
              style: pw.TextStyle(font: fonts.regular, fontSize: 9),
            ),
          if (data.customerAddress != null && data.customerAddress!.isNotEmpty)
            pw.Text(
              '${_t('address', lang)}: ${data.customerAddress}',
              style: pw.TextStyle(font: fonts.regular, fontSize: 9),
            ),
        ],
      ),
    );
  }

  static pw.Widget _buildBalanceSummary(
    CustomerStatementData data,
    CurrencyService cs,
    _PdfFonts fonts,
    String lang,
  ) {
    return pw.TableHelper.fromTextArray(
      headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 9),
      cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 9),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      cellAlignments: {
        0: pw.Alignment.centerRight,
        1: pw.Alignment.centerRight,
        2: pw.Alignment.centerRight,
        3: pw.Alignment.centerRight,
      },
      headers: [
        _t('opening_balance', lang),
        _t('total_debits', lang),
        _t('total_credits', lang),
        _t('closing_balance', lang),
      ],
      data: [
        [
          cs.formatCents(data.openingBalanceCents),
          cs.formatCents(data.totalDebitsCents),
          cs.formatCents(data.totalCreditsCents),
          cs.formatCents(data.closingBalanceCents),
        ],
      ],
    );
  }

  static pw.Widget _buildTransactionTable(
    CustomerStatementData data,
    CurrencyService cs,
    _PdfFonts fonts,
    String lang,
  ) {
    final rows = <List<String>>[];

    // Opening balance row
    rows.add([
      DateFormat.yMd().format(data.dateRange.startDate),
      _t('opening_balance', lang),
      '-',
      '-',
      '-',
      cs.formatCents(data.openingBalanceCents),
    ]);

    // Transaction rows
    for (final txn in data.transactions) {
      final isDebit = txn.amountCents > 0;
      rows.add([
        DateFormat.yMd().format(txn.date),
        _tTxnType(txn.type, lang),
        txn.description ?? '-',
        isDebit ? cs.formatCents(txn.amountCents) : '-',
        !isDebit ? cs.formatCents(txn.amountCents.abs()) : '-',
        cs.formatCents(txn.runningBalanceCents),
      ]);
    }

    // Closing balance row
    rows.add([
      DateFormat.yMd().format(data.dateRange.endDate),
      _t('closing_balance', lang),
      '-',
      cs.formatCents(data.totalDebitsCents),
      cs.formatCents(data.totalCreditsCents),
      cs.formatCents(data.closingBalanceCents),
    ]);

    return pw.TableHelper.fromTextArray(
      headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 8),
      cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 8),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.centerLeft,
        3: pw.Alignment.centerRight,
        4: pw.Alignment.centerRight,
        5: pw.Alignment.centerRight,
      },
      headers: [
        _t('date', lang),
        _t('type', lang),
        _t('description', lang),
        _t('debit', lang),
        _t('credit', lang),
        _t('balance', lang),
      ],
      data: rows,
    );
  }

  // ═══════════════════════════════════════════════════════
  // 3-LANGUAGE TRANSLATIONS FOR PDF
  // ═══════════════════════════════════════════════════════

  static const _translations = {
    'customer_statement': {
      'en': 'Customer Statement',
      'ar': 'كشف حساب العميل',
      'fr': 'Relevé de Compte Client',
    },
    'period': {
      'en': 'Period',
      'ar': 'الفترة',
      'fr': 'Période',
    },
    'customer': {
      'en': 'Customer',
      'ar': 'العميل',
      'fr': 'Client',
    },
    'phone': {
      'en': 'Phone',
      'ar': 'الهاتف',
      'fr': 'Téléphone',
    },
    'email': {
      'en': 'Email',
      'ar': 'البريد الإلكتروني',
      'fr': 'E-mail',
    },
    'address': {
      'en': 'Address',
      'ar': 'العنوان',
      'fr': 'Adresse',
    },
    'opening_balance': {
      'en': 'Opening Balance',
      'ar': 'الرصيد الافتتاحي',
      'fr': 'Solde d\'Ouverture',
    },
    'closing_balance': {
      'en': 'Closing Balance',
      'ar': 'الرصيد الختامي',
      'fr': 'Solde de Clôture',
    },
    'total_debits': {
      'en': 'Total Debits',
      'ar': 'إجمالي المدين',
      'fr': 'Total Débits',
    },
    'total_credits': {
      'en': 'Total Credits',
      'ar': 'إجمالي الدائن',
      'fr': 'Total Crédits',
    },
    'transactions': {
      'en': 'Transactions',
      'ar': 'المعاملات',
      'fr': 'Transactions',
    },
    'date': {
      'en': 'Date',
      'ar': 'التاريخ',
      'fr': 'Date',
    },
    'type': {
      'en': 'Type',
      'ar': 'النوع',
      'fr': 'Type',
    },
    'description': {
      'en': 'Description',
      'ar': 'الوصف',
      'fr': 'Description',
    },
    'debit': {
      'en': 'Debit',
      'ar': 'مدين',
      'fr': 'Débit',
    },
    'credit': {
      'en': 'Credit',
      'ar': 'دائن',
      'fr': 'Crédit',
    },
    'balance': {
      'en': 'Balance',
      'ar': 'الرصيد',
      'fr': 'Solde',
    },
    'no_transactions': {
      'en': 'No transactions in this period',
      'ar': 'لا توجد معاملات في هذه الفترة',
      'fr': 'Aucune transaction pour cette période',
    },
    'printed_on': {
      'en': 'Printed on',
      'ar': 'طُبع في',
      'fr': 'Imprimé le',
    },
    // Transaction types
    'txn_sale': {
      'en': 'Sale',
      'ar': 'بيع',
      'fr': 'Vente',
    },
    'txn_payment': {
      'en': 'Payment',
      'ar': 'دفعة',
      'fr': 'Paiement',
    },
    'txn_return': {
      'en': 'Return',
      'ar': 'مرتجع',
      'fr': 'Retour',
    },
    'txn_refund': {
      'en': 'Refund',
      'ar': 'استرداد',
      'fr': 'Remboursement',
    },
    'txn_adjustment': {
      'en': 'Adjustment',
      'ar': 'تسوية',
      'fr': 'Ajustement',
    },
    'txn_credit_note': {
      'en': 'Credit Note',
      'ar': 'إشعار دائن',
      'fr': 'Note de Crédit',
    },
    'txn_opening_balance': {
      'en': 'Opening Balance',
      'ar': 'رصيد افتتاحي',
      'fr': 'Solde d\'Ouverture',
    },
  };

  static String _t(String key, String lang) {
    return _translations[key]?[lang] ?? _translations[key]?['en'] ?? key;
  }

  static String _tTxnType(String type, String lang) {
    final key = 'txn_$type';
    return _translations[key]?[lang] ?? _translations[key]?['en'] ?? type;
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
                color: PdfColors.grey600),
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
      final regularData =
          await rootBundle.load('assets/fonts/IBMPlexSansArabic-Regular.ttf');
      final boldData =
          await rootBundle.load('assets/fonts/IBMPlexSansArabic-Bold.ttf');
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
