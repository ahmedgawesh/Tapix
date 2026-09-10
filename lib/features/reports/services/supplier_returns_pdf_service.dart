import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../core/di/injection_container.dart';
import '../../../core/services/currency_service.dart';
import '../../settings/data/services/company_profile_service.dart';
import '../presentation/bloc/supplier_returns_report_bloc.dart';
import 'invoices_pdf_builder.dart';

class SupplierReturnsPdfService {
  static String _referenceLabel(SupplierReturnInvoice r) {
    if (r.isLinked) {
      final ref = r.originalInvoiceNumber;
      if (ref == null || ref.isEmpty) {
        return 'reports.return_linked'.tr();
      }
      return '${'reports.return_linked'.tr()} · ${'reports.original_invoice'.tr()}: $ref';
    }
    return 'reports.return_adjustment'.tr();
  }

  static List<InvoicePdfItem> _mapReturns(SupplierReturnsData data) {
    return data.returns
        .map(
          (r) => InvoicePdfItem(
            invoiceNumber: r.returnNumber,
            referenceLabel: _referenceLabel(r),
            date: r.date,
            items: r.items,
            subtotalCents: r.subtotalCents,
            discountCents: r.discountCents,
            taxCents: r.taxCents,
            totalCents: r.totalCents,
            // Returns are settled in full against the supplier balance.
            paidAmountCents: r.totalCents,
            paymentMethod: r.refundMethod,
          ),
        )
        .toList();
  }

  static Future<void> printReport({
    required BuildContext context,
    required SupplierReturnsData data,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final company = await sl<CompanyProfileService>().getProfile();

    final pdf = await InvoicesPdfBuilder.build(
      title: 'reports.supplier_returns_report'.tr(),
      partyLabel: 'reports.supplier'.tr(),
      partyName: data.supplierName ?? '',
      partyPhone: data.supplierPhone,
      partyAddress: data.supplierAddress,
      startDate: data.dateRange.startDate,
      endDate: data.dateRange.endDate,
      invoices: _mapReturns(data),
      totalAmountCents: data.totalAmountCents,
      totalDiscountCents: data.totalDiscountCents,
      totalPaidCents: data.totalAmountCents,
      cs: cs,
      locale: locale,
      isRtl: locale.languageCode == 'ar',
      company: company,
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name:
          'SupplierReturns_${data.supplierName ?? ''}_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  static Future<void> shareReport({
    required BuildContext context,
    required SupplierReturnsData data,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final company = await sl<CompanyProfileService>().getProfile();

    final pdf = await InvoicesPdfBuilder.build(
      title: 'reports.supplier_returns_report'.tr(),
      partyLabel: 'reports.supplier'.tr(),
      partyName: data.supplierName ?? '',
      partyPhone: data.supplierPhone,
      partyAddress: data.supplierAddress,
      startDate: data.dateRange.startDate,
      endDate: data.dateRange.endDate,
      invoices: _mapReturns(data),
      totalAmountCents: data.totalAmountCents,
      totalDiscountCents: data.totalDiscountCents,
      totalPaidCents: data.totalAmountCents,
      cs: cs,
      locale: locale,
      isRtl: locale.languageCode == 'ar',
      company: company,
    );

    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'SupplierReturns_${data.supplierName ?? ''}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }
}
