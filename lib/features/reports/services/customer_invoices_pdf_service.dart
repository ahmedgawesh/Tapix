import '../presentation/widgets/warehouse_report_context.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../core/di/injection_container.dart';
import '../../../core/services/currency_service.dart';
import '../../settings/data/services/company_profile_service.dart';
import '../presentation/bloc/customer_invoices_report_bloc.dart';
import 'invoices_pdf_builder.dart';

class CustomerInvoicesPdfService {
  static List<InvoicePdfItem> _mapInvoices(CustomerInvoicesData data) {
    return data.invoices
        .map(
          (inv) => InvoicePdfItem(
            invoiceNumber: inv.invoiceNumber,
            date: inv.date,
            items: inv.items,
            subtotalCents: inv.subtotalCents,
            discountCents: inv.discountCents,
            taxCents: inv.taxCents,
            totalCents: inv.totalCents,
            paidAmountCents: inv.paidAmountCents,
            paymentMethod: inv.paymentMethod,
          ),
        )
        .toList();
  }

  static Future<void> printReport({
    required BuildContext context,
    required CustomerInvoicesData data,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final reportLocation = WarehouseReportContext.maybeOf(context);
    await reportLocation?.scope.checkAccess();
    final loadedCompany = await sl<CompanyProfileService>().getProfile();
    final company =
        reportLocation?.decorateCompany(loadedCompany) ?? loadedCompany;

    final pdf = await InvoicesPdfBuilder.build(
      title: 'reports.customer_invoices_report'.tr(),
      partyLabel: 'reports.customer'.tr(),
      partyName: data.customerName ?? '',
      partyPhone: data.customerPhone,
      partyAddress: data.customerAddress,
      startDate: data.dateRange.startDate,
      endDate: data.dateRange.endDate,
      invoices: _mapInvoices(data),
      totalAmountCents: data.totalAmountCents,
      totalDiscountCents: data.totalDiscountCents,
      totalPaidCents: data.totalPaidCents,
      cs: cs,
      locale: locale,
      isRtl: locale.languageCode == 'ar',
      company: company,
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name:
          'CustomerInvoices_${data.customerName ?? ''}_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  static Future<void> shareReport({
    required BuildContext context,
    required CustomerInvoicesData data,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final reportLocation = WarehouseReportContext.maybeOf(context);
    await reportLocation?.scope.checkAccess();
    final loadedCompany = await sl<CompanyProfileService>().getProfile();
    final company =
        reportLocation?.decorateCompany(loadedCompany) ?? loadedCompany;

    final pdf = await InvoicesPdfBuilder.build(
      title: 'reports.customer_invoices_report'.tr(),
      partyLabel: 'reports.customer'.tr(),
      partyName: data.customerName ?? '',
      partyPhone: data.customerPhone,
      partyAddress: data.customerAddress,
      startDate: data.dateRange.startDate,
      endDate: data.dateRange.endDate,
      invoices: _mapInvoices(data),
      totalAmountCents: data.totalAmountCents,
      totalDiscountCents: data.totalDiscountCents,
      totalPaidCents: data.totalPaidCents,
      cs: cs,
      locale: locale,
      isRtl: locale.languageCode == 'ar',
      company: company,
    );

    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'CustomerInvoices_${data.customerName ?? ''}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }
}
