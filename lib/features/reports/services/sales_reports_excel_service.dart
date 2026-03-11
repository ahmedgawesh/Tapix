import 'dart:io';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

import '../../../core/di/injection_container.dart';
import '../../../core/services/currency_service.dart';
import '../presentation/bloc/sales_reports_bloc.dart';

class SalesReportsExcelService {
  /// Export sales invoices to Excel and share
  static Future<void> exportSales({
    required BuildContext context,
    required SalesReportsData data,
  }) async {
    final cs = sl<CurrencyService>();
    final lang = context.locale.languageCode;
    final excel = Excel.createExcel();

    // Sales sheet
    final sheet = excel['Sales'];
    excel.delete('Sheet1');

    // Header row
    sheet.appendRow([
      TextCellValue(_t('invoice_number', lang)),
      TextCellValue(_t('customer', lang)),
      TextCellValue(_t('subtotal', lang)),
      TextCellValue(_t('discount', lang)),
      TextCellValue(_t('tax', lang)),
      TextCellValue(_t('total', lang)),
      TextCellValue(_t('paid', lang)),
      TextCellValue(_t('payment_method', lang)),
      TextCellValue(_t('status', lang)),
      TextCellValue(_t('date', lang)),
    ]);

    // Data rows
    for (final s in data.allSales) {
      sheet.appendRow([
        TextCellValue(s.invoiceNumber),
        TextCellValue(s.customerName ?? '-'),
        TextCellValue(cs.formatCents(s.subtotalCents)),
        TextCellValue(cs.formatCents(s.discountCents)),
        TextCellValue(cs.formatCents(s.taxCents)),
        TextCellValue(cs.formatCents(s.totalCents)),
        TextCellValue(cs.formatCents(s.paidAmountCents)),
        TextCellValue(_paymentLabel(s.paymentMethod, lang)),
        TextCellValue(s.status),
        TextCellValue(DateFormat.yMd().format(s.saleDate)),
      ]);
    }

    // Summary row
    sheet.appendRow([]);
    sheet.appendRow([
      TextCellValue(_t('total', lang)),
      TextCellValue(''),
      TextCellValue(cs.formatCents(data.summary.totalSalesCents - data.summary.totalDiscountCents - data.summary.totalTaxCents)),
      TextCellValue(cs.formatCents(data.summary.totalDiscountCents)),
      TextCellValue(cs.formatCents(data.summary.totalTaxCents)),
      TextCellValue(cs.formatCents(data.summary.totalSalesCents)),
      TextCellValue(cs.formatCents(data.summary.totalPaidCents)),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue('${_t('invoices', lang)}: ${data.summary.invoiceCount}'),
    ]);

    await _saveAndShare(excel, 'Sales_${DateFormat('yyyyMMdd').format(DateTime.now())}');
  }

  /// Export sales with product details to Excel and share
  static Future<void> exportSalesWithProducts({
    required BuildContext context,
    required SalesReportsData data,
  }) async {
    final cs = sl<CurrencyService>();
    final lang = context.locale.languageCode;
    final excel = Excel.createExcel();

    // Sales sheet
    final salesSheet = excel['Sales'];
    excel.delete('Sheet1');

    salesSheet.appendRow([
      TextCellValue(_t('invoice_number', lang)),
      TextCellValue(_t('customer', lang)),
      TextCellValue(_t('subtotal', lang)),
      TextCellValue(_t('discount', lang)),
      TextCellValue(_t('tax', lang)),
      TextCellValue(_t('total', lang)),
      TextCellValue(_t('paid', lang)),
      TextCellValue(_t('payment_method', lang)),
      TextCellValue(_t('date', lang)),
    ]);

    for (final s in data.allSales) {
      salesSheet.appendRow([
        TextCellValue(s.invoiceNumber),
        TextCellValue(s.customerName ?? '-'),
        TextCellValue(cs.formatCents(s.subtotalCents)),
        TextCellValue(cs.formatCents(s.discountCents)),
        TextCellValue(cs.formatCents(s.taxCents)),
        TextCellValue(cs.formatCents(s.totalCents)),
        TextCellValue(cs.formatCents(s.paidAmountCents)),
        TextCellValue(_paymentLabel(s.paymentMethod, lang)),
        TextCellValue(DateFormat.yMd().format(s.saleDate)),
      ]);
    }

    // Products sheet
    final productsSheet = excel['Products'];
    productsSheet.appendRow([
      TextCellValue(_t('product', lang)),
      TextCellValue(_t('category', lang)),
      TextCellValue(_t('quantity', lang)),
      TextCellValue(_t('total_sales', lang)),
      TextCellValue(_t('discount', lang)),
      TextCellValue(_t('tax', lang)),
      TextCellValue(_t('invoices', lang)),
    ]);

    for (final p in data.byProduct) {
      productsSheet.appendRow([
        TextCellValue(p.productName),
        TextCellValue(p.categoryName ?? '-'),
        IntCellValue(p.totalQuantity),
        TextCellValue(cs.formatCents(p.totalSalesCents)),
        TextCellValue(cs.formatCents(p.totalDiscountCents)),
        TextCellValue(cs.formatCents(p.totalTaxCents)),
        IntCellValue(p.invoiceCount),
      ]);
    }

    // Categories sheet
    final categoriesSheet = excel['Categories'];
    categoriesSheet.appendRow([
      TextCellValue(_t('category', lang)),
      TextCellValue(_t('products', lang)),
      TextCellValue(_t('quantity', lang)),
      TextCellValue(_t('total_sales', lang)),
      TextCellValue(_t('discount', lang)),
      TextCellValue(_t('tax', lang)),
      TextCellValue(_t('invoices', lang)),
    ]);

    for (final c in data.byCategory) {
      categoriesSheet.appendRow([
        TextCellValue(c.categoryName),
        IntCellValue(c.productCount),
        IntCellValue(c.totalQuantity),
        TextCellValue(cs.formatCents(c.totalSalesCents)),
        TextCellValue(cs.formatCents(c.totalDiscountCents)),
        TextCellValue(cs.formatCents(c.totalTaxCents)),
        IntCellValue(c.invoiceCount),
      ]);
    }

    // Customers sheet
    final customersSheet = excel['Customers'];
    customersSheet.appendRow([
      TextCellValue(_t('customer', lang)),
      TextCellValue(_t('total_sales', lang)),
      TextCellValue(_t('discount', lang)),
      TextCellValue(_t('tax', lang)),
      TextCellValue(_t('invoices', lang)),
      TextCellValue(_t('quantity', lang)),
      TextCellValue(_t('last_sale', lang)),
    ]);

    for (final c in data.byCustomer) {
      customersSheet.appendRow([
        TextCellValue(c.customerName),
        TextCellValue(cs.formatCents(c.totalSalesCents)),
        TextCellValue(cs.formatCents(c.totalDiscountCents)),
        TextCellValue(cs.formatCents(c.totalTaxCents)),
        IntCellValue(c.invoiceCount),
        IntCellValue(c.totalQuantity),
        TextCellValue(c.lastSaleDate != null ? DateFormat.yMd().format(c.lastSaleDate!) : '-'),
      ]);
    }

    await _saveAndShare(excel, 'SalesWithProducts_${DateFormat('yyyyMMdd').format(DateTime.now())}');
  }

  // ═══════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════

  static Future<void> _saveAndShare(Excel excel, String filename) async {
    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/$filename.xlsx';
    final fileBytes = excel.save();
    if (fileBytes == null) return;

    final file = File(filePath);
    await file.writeAsBytes(fileBytes);

    await Printing.sharePdf(
      bytes: Uint8List.fromList(fileBytes),
      filename: '$filename.xlsx',
    );
  }

  static String _paymentLabel(String method, String lang) {
    switch (method) {
      case 'cash':
        return _t('payment_cash', lang);
      case 'credit':
        return _t('payment_credit', lang);
      case 'card':
        return _t('payment_card', lang);
      case 'cheque':
        return _t('payment_cheque', lang);
      default:
        return method;
    }
  }

  static const _translations = {
    'invoice_number': {'en': 'Invoice #', 'ar': 'رقم الفاتورة', 'fr': 'Facture #'},
    'customer': {'en': 'Customer', 'ar': 'العميل', 'fr': 'Client'},
    'subtotal': {'en': 'Subtotal', 'ar': 'المجموع الفرعي', 'fr': 'Sous-total'},
    'discount': {'en': 'Discount', 'ar': 'الخصم', 'fr': 'Remise'},
    'tax': {'en': 'Tax', 'ar': 'الضريبة', 'fr': 'Taxe'},
    'total': {'en': 'Total', 'ar': 'الإجمالي', 'fr': 'Total'},
    'paid': {'en': 'Paid', 'ar': 'المدفوع', 'fr': 'Payé'},
    'payment_method': {'en': 'Payment', 'ar': 'الدفع', 'fr': 'Paiement'},
    'status': {'en': 'Status', 'ar': 'الحالة', 'fr': 'Statut'},
    'date': {'en': 'Date', 'ar': 'التاريخ', 'fr': 'Date'},
    'invoices': {'en': 'Invoices', 'ar': 'الفواتير', 'fr': 'Factures'},
    'product': {'en': 'Product', 'ar': 'المنتج', 'fr': 'Produit'},
    'category': {'en': 'Category', 'ar': 'التصنيف', 'fr': 'Catégorie'},
    'products': {'en': 'Products', 'ar': 'المنتجات', 'fr': 'Produits'},
    'quantity': {'en': 'Qty', 'ar': 'الكمية', 'fr': 'Qté'},
    'total_sales': {'en': 'Total Sales', 'ar': 'إجمالي المبيعات', 'fr': 'Total Ventes'},
    'last_sale': {'en': 'Last Sale', 'ar': 'آخر بيع', 'fr': 'Dernière Vente'},
    'payment_cash': {'en': 'Cash', 'ar': 'نقد', 'fr': 'Espèces'},
    'payment_credit': {'en': 'Credit', 'ar': 'آجل', 'fr': 'Crédit'},
    'payment_card': {'en': 'Card', 'ar': 'بطاقة', 'fr': 'Carte'},
    'payment_cheque': {'en': 'Cheque', 'ar': 'شيك', 'fr': 'Chèque'},
  };

  static String _t(String key, String lang) {
    return _translations[key]?[lang] ?? _translations[key]?['en'] ?? key;
  }
}
