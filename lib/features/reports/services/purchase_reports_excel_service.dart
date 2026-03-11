import 'dart:io';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

import '../../../core/di/injection_container.dart';
import '../../../core/services/currency_service.dart';
import '../presentation/bloc/purchase_reports_bloc.dart';

class PurchaseReportsExcelService {
  /// Export purchase invoices to Excel and share
  static Future<void> exportPurchases({
    required BuildContext context,
    required PurchaseReportsData data,
  }) async {
    final cs = sl<CurrencyService>();
    final lang = context.locale.languageCode;
    final excel = Excel.createExcel();

    final sheet = excel['Purchases'];
    excel.delete('Sheet1');

    sheet.appendRow([
      TextCellValue(_t('purchase_number', lang)),
      TextCellValue(_t('supplier', lang)),
      TextCellValue(_t('subtotal', lang)),
      TextCellValue(_t('discount', lang)),
      TextCellValue(_t('tax', lang)),
      TextCellValue(_t('total', lang)),
      TextCellValue(_t('paid', lang)),
      TextCellValue(_t('payment_method', lang)),
      TextCellValue(_t('status', lang)),
      TextCellValue(_t('date', lang)),
    ]);

    for (final p in data.allPurchases) {
      sheet.appendRow([
        TextCellValue(p.purchaseNumber),
        TextCellValue(p.supplierName),
        TextCellValue(cs.formatCents(p.subtotalCents)),
        TextCellValue(cs.formatCents(p.discountCents)),
        TextCellValue(cs.formatCents(p.taxCents)),
        TextCellValue(cs.formatCents(p.totalCents)),
        TextCellValue(cs.formatCents(p.paidAmountCents)),
        TextCellValue(_paymentLabel(p.paymentMethod, lang)),
        TextCellValue(p.status),
        TextCellValue(DateFormat.yMd().format(p.purchaseDate)),
      ]);
    }

    sheet.appendRow([]);
    sheet.appendRow([
      TextCellValue(_t('total', lang)),
      TextCellValue(''),
      TextCellValue(cs.formatCents(data.summary.totalPurchasesCents - data.summary.totalDiscountCents - data.summary.totalTaxCents)),
      TextCellValue(cs.formatCents(data.summary.totalDiscountCents)),
      TextCellValue(cs.formatCents(data.summary.totalTaxCents)),
      TextCellValue(cs.formatCents(data.summary.totalPurchasesCents)),
      TextCellValue(cs.formatCents(data.summary.totalPaidCents)),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue('${_t('invoices', lang)}: ${data.summary.invoiceCount}'),
    ]);

    await _saveAndShare(excel, 'Purchases_${DateFormat('yyyyMMdd').format(DateTime.now())}');
  }

  /// Export purchases with product details to Excel and share
  static Future<void> exportPurchasesWithProducts({
    required BuildContext context,
    required PurchaseReportsData data,
  }) async {
    final cs = sl<CurrencyService>();
    final lang = context.locale.languageCode;
    final excel = Excel.createExcel();

    // Purchases sheet
    final purchasesSheet = excel['Purchases'];
    excel.delete('Sheet1');

    purchasesSheet.appendRow([
      TextCellValue(_t('purchase_number', lang)),
      TextCellValue(_t('supplier', lang)),
      TextCellValue(_t('subtotal', lang)),
      TextCellValue(_t('discount', lang)),
      TextCellValue(_t('tax', lang)),
      TextCellValue(_t('total', lang)),
      TextCellValue(_t('paid', lang)),
      TextCellValue(_t('payment_method', lang)),
      TextCellValue(_t('date', lang)),
    ]);

    for (final p in data.allPurchases) {
      purchasesSheet.appendRow([
        TextCellValue(p.purchaseNumber),
        TextCellValue(p.supplierName),
        TextCellValue(cs.formatCents(p.subtotalCents)),
        TextCellValue(cs.formatCents(p.discountCents)),
        TextCellValue(cs.formatCents(p.taxCents)),
        TextCellValue(cs.formatCents(p.totalCents)),
        TextCellValue(cs.formatCents(p.paidAmountCents)),
        TextCellValue(_paymentLabel(p.paymentMethod, lang)),
        TextCellValue(DateFormat.yMd().format(p.purchaseDate)),
      ]);
    }

    // Products sheet
    final productsSheet = excel['Products'];
    productsSheet.appendRow([
      TextCellValue(_t('product', lang)),
      TextCellValue(_t('category', lang)),
      TextCellValue(_t('quantity', lang)),
      TextCellValue(_t('total_purchases', lang)),
      TextCellValue(_t('discount', lang)),
      TextCellValue(_t('tax', lang)),
      TextCellValue(_t('invoices', lang)),
    ]);

    for (final p in data.byProduct) {
      productsSheet.appendRow([
        TextCellValue(p.productName),
        TextCellValue(p.categoryName ?? '-'),
        IntCellValue(p.totalQuantity),
        TextCellValue(cs.formatCents(p.totalPurchasesCents)),
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
      TextCellValue(_t('total_purchases', lang)),
      TextCellValue(_t('discount', lang)),
      TextCellValue(_t('tax', lang)),
      TextCellValue(_t('invoices', lang)),
    ]);

    for (final c in data.byCategory) {
      categoriesSheet.appendRow([
        TextCellValue(c.categoryName),
        IntCellValue(c.productCount),
        IntCellValue(c.totalQuantity),
        TextCellValue(cs.formatCents(c.totalPurchasesCents)),
        TextCellValue(cs.formatCents(c.totalDiscountCents)),
        TextCellValue(cs.formatCents(c.totalTaxCents)),
        IntCellValue(c.invoiceCount),
      ]);
    }

    // Suppliers sheet
    final suppliersSheet = excel['Suppliers'];
    suppliersSheet.appendRow([
      TextCellValue(_t('supplier', lang)),
      TextCellValue(_t('total_purchases', lang)),
      TextCellValue(_t('discount', lang)),
      TextCellValue(_t('tax', lang)),
      TextCellValue(_t('invoices', lang)),
      TextCellValue(_t('quantity', lang)),
      TextCellValue(_t('last_purchase', lang)),
    ]);

    for (final s in data.bySupplier) {
      suppliersSheet.appendRow([
        TextCellValue(s.supplierName),
        TextCellValue(cs.formatCents(s.totalPurchasesCents)),
        TextCellValue(cs.formatCents(s.totalDiscountCents)),
        TextCellValue(cs.formatCents(s.totalTaxCents)),
        IntCellValue(s.invoiceCount),
        IntCellValue(s.totalQuantity),
        TextCellValue(s.lastPurchaseDate != null ? DateFormat.yMd().format(s.lastPurchaseDate!) : '-'),
      ]);
    }

    await _saveAndShare(excel, 'PurchasesWithProducts_${DateFormat('yyyyMMdd').format(DateTime.now())}');
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

  static String _paymentLabel(String? method, String lang) {
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
        return method ?? '-';
    }
  }

  static const _translations = {
    'purchase_number': {'en': 'Purchase #', 'ar': 'رقم الفاتورة', 'fr': 'Achat #'},
    'supplier': {'en': 'Supplier', 'ar': 'المورد', 'fr': 'Fournisseur'},
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
    'total_purchases': {'en': 'Total Purchases', 'ar': 'إجمالي المشتريات', 'fr': 'Total Achats'},
    'last_purchase': {'en': 'Last Purchase', 'ar': 'آخر شراء', 'fr': 'Dernier Achat'},
    'payment_cash': {'en': 'Cash', 'ar': 'نقد', 'fr': 'Espèces'},
    'payment_credit': {'en': 'Credit', 'ar': 'آجل', 'fr': 'Crédit'},
    'payment_card': {'en': 'Card', 'ar': 'بطاقة', 'fr': 'Carte'},
    'payment_cheque': {'en': 'Cheque', 'ar': 'شيك', 'fr': 'Chèque'},
  };

  static String _t(String key, String lang) {
    return _translations[key]?[lang] ?? _translations[key]?['en'] ?? key;
  }
}
