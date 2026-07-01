import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../core/di/injection_container.dart';
import '../../../core/services/currency_service.dart';
import '../../settings/data/services/company_profile_service.dart';
import '../presentation/bloc/supplier_invoices_report_bloc.dart';
import 'invoices_pdf_builder.dart';

class SupplierInvoicesPdfService {
  static List<InvoicePdfItem> _mapInvoices(SupplierInvoicesData data) {
    return data.invoices
        .map((inv) => InvoicePdfItem(
              invoiceNumber: inv.invoiceNumber,
              referenceLabel: inv.supplierInvoiceRef == null
                  ? null
                  : '${'reports.supplier_invoice_ref'.tr()}: ${inv.supplierInvoiceRef}',
              date: inv.date,
              items: inv.items,
              subtotalCents: inv.subtotalCents,
              discountCents: inv.discountCents,
              taxCents: inv.taxCents,
              totalCents: inv.totalCents,
              paidAmountCents: inv.paidAmountCents,
              paymentMethod: inv.paymentMethod,
            ))
        .toList();
  }

  static Future<void> printReport({
    required BuildContext context,
    required SupplierInvoicesData data,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final company = await sl<CompanyProfileService>().getProfile();

    final pdf = await InvoicesPdfBuilder.build(
      title: 'reports.supplier_invoices_report'.tr(),
      partyLabel: 'reports.supplier'.tr(),
      partyName: data.supplierName ?? '',
      partyPhone: data.supplierPhone,
      partyAddress: data.supplierAddress,
      startDate: data.dateRange.startDate,
      endDate: data.dateRange.endDate,
      invoices: _mapInvoices(data),
      totalAmountCents: data.totalAmountCents,
      totalDiscountCents: data.totalDiscountCents,
      totalPaidCents: data.totalPaidCents,
      totalQuantity: data.totalQuantity,
      cs: cs,
      locale: locale,
      isRtl: locale.languageCode == 'ar',
      company: company,
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name:
          'SupplierInvoices_${data.supplierName ?? ''}_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  static Future<void> shareReport({
    required BuildContext context,
    required SupplierInvoicesData data,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final company = await sl<CompanyProfileService>().getProfile();

    final pdf = await InvoicesPdfBuilder.build(
      title: 'reports.supplier_invoices_report'.tr(),
      partyLabel: 'reports.supplier'.tr(),
      partyName: data.supplierName ?? '',
      partyPhone: data.supplierPhone,
      partyAddress: data.supplierAddress,
      startDate: data.dateRange.startDate,
      endDate: data.dateRange.endDate,
      invoices: _mapInvoices(data),
      totalAmountCents: data.totalAmountCents,
      totalDiscountCents: data.totalDiscountCents,
      totalPaidCents: data.totalPaidCents,
      totalQuantity: data.totalQuantity,
      cs: cs,
      locale: locale,
      isRtl: locale.languageCode == 'ar',
      company: company,
    );

    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'SupplierInvoices_${data.supplierName ?? ''}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }
}
