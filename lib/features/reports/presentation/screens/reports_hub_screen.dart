import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../bloc/reports_bloc.dart';
import '../widgets/report_scrollable_center.dart';

class ReportsHubScreen extends StatelessWidget {
  const ReportsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          sl<ReportsBloc>()..add(const ReportsReconciliationRequested()),
      child: const _ReportsHubView(),
    );
  }
}

// ── Data model for a single report tile ──
class _ReportEntry {
  final IconData icon;
  final String titleKey;
  final String subtitleKey;
  final String route;
  final String sectionKey;
  final List<String> searchKeyKeys;
  final bool showInOverview;

  const _ReportEntry({
    required this.icon,
    required this.titleKey,
    required this.subtitleKey,
    required this.route,
    required this.sectionKey,
    this.searchKeyKeys = const [],
    this.showInOverview = true,
  });
}

// Section ordering to preserve the original layout.
const _kSectionOrder = <String>[
  'reports.sales_reports',
  'reports.purchase_reports',
  'reports.discount_reports',
  'reports.profit_reports',
  'financial_management.financial_reports',
  'reports.inventory_reports',
  'reports.customer_reports',
  'reports.supplier_reports',
  'reports.tax_reports',
  'reports.salespeople_reports',
  'reports.expense_reports',
  'reports.cheque_reports',
  'reports.diagnostics',
];

// All report tiles in their original order, grouped by section key.
const _kAllReports = <_ReportEntry>[
  // ── Sales Reports ──
  _ReportEntry(
    icon: LucideIcons.truck,
    titleKey: 'reports.sales_by_supplier',
    subtitleKey: 'reports.sales_by_supplier_desc',
    route: '/reports/sales/by-supplier',
    sectionKey: 'reports.sales_reports',
    searchKeyKeys: ['reports.sales_product_reports'],
    showInOverview: false,
  ),
  _ReportEntry(
    icon: LucideIcons.shoppingCart,
    titleKey: 'reports.sales_reports',
    subtitleKey: 'reports.sales_reports_desc',
    route: '/reports/sales',
    sectionKey: 'reports.sales_reports',
  ),
  _ReportEntry(
    icon: LucideIcons.calendarDays,
    titleKey: 'reports.sales_by_period',
    subtitleKey: 'reports.sales_by_period_desc',
    route: '/reports/sales/by-period',
    sectionKey: 'reports.sales_reports',
    searchKeyKeys: ['reports.sales_period_reports'],
    showInOverview: false,
  ),
  _ReportEntry(
    icon: LucideIcons.banknote,
    titleKey: 'reports.cash_sales',
    subtitleKey: 'reports.cash_sales_desc',
    route: '/reports/sales/cash',
    sectionKey: 'reports.sales_reports',
    searchKeyKeys: ['reports.sales_period_reports'],
    showInOverview: false,
  ),
  _ReportEntry(
    icon: LucideIcons.clock,
    titleKey: 'reports.credit_sales',
    subtitleKey: 'reports.credit_sales_desc',
    route: '/reports/sales/credit',
    sectionKey: 'reports.sales_reports',
    searchKeyKeys: ['reports.sales_period_reports'],
    showInOverview: false,
  ),
  _ReportEntry(
    icon: LucideIcons.creditCard,
    titleKey: 'reports.card_sales',
    subtitleKey: 'reports.card_sales_desc',
    route: '/reports/sales/card',
    sectionKey: 'reports.sales_reports',
    searchKeyKeys: ['reports.sales_period_reports'],
    showInOverview: false,
  ),
  _ReportEntry(
    icon: LucideIcons.fileText,
    titleKey: 'reports.cheque_sales',
    subtitleKey: 'reports.cheque_sales_desc',
    route: '/reports/sales/cheque',
    sectionKey: 'reports.sales_reports',
    searchKeyKeys: ['reports.sales_period_reports'],
    showInOverview: false,
  ),
  _ReportEntry(
    icon: LucideIcons.listOrdered,
    titleKey: 'reports.all_sales',
    subtitleKey: 'reports.all_sales_desc',
    route: '/reports/sales/all',
    sectionKey: 'reports.sales_reports',
    searchKeyKeys: ['reports.sales_period_reports'],
    showInOverview: false,
  ),
  _ReportEntry(
    icon: LucideIcons.package2,
    titleKey: 'reports.sales_by_product',
    subtitleKey: 'reports.sales_by_product_desc',
    route: '/reports/sales/by-product',
    sectionKey: 'reports.sales_reports',
    searchKeyKeys: ['reports.sales_product_reports'],
    showInOverview: false,
  ),
  _ReportEntry(
    icon: LucideIcons.folderOpen,
    titleKey: 'reports.sales_by_category',
    subtitleKey: 'reports.sales_by_category_desc',
    route: '/reports/sales/by-category',
    sectionKey: 'reports.sales_reports',
    searchKeyKeys: ['reports.sales_product_reports'],
    showInOverview: false,
  ),
  _ReportEntry(
    icon: LucideIcons.users,
    titleKey: 'reports.sales_by_customer',
    subtitleKey: 'reports.sales_by_customer_desc',
    route: '/reports/sales/by-customer',
    sectionKey: 'reports.sales_reports',
    searchKeyKeys: ['reports.sales_customer_reports'],
    showInOverview: false,
  ),
  _ReportEntry(
    icon: LucideIcons.ban,
    titleKey: 'reports.cancelled_invoices',
    subtitleKey: 'reports.cancelled_invoices_desc',
    route: '/reports/sales/cancelled',
    sectionKey: 'reports.sales_reports',
    searchKeyKeys: ['reports.sales_other_reports'],
    showInOverview: false,
  ),
  _ReportEntry(
    icon: LucideIcons.receipt,
    titleKey: 'reports.tax_by_product',
    subtitleKey: 'reports.tax_by_product_desc',
    route: '/reports/sales/tax-by-product',
    sectionKey: 'reports.sales_reports',
    searchKeyKeys: ['reports.sales_other_reports'],
    showInOverview: false,
  ),
  _ReportEntry(
    icon: LucideIcons.userCheck,
    titleKey: 'reports.tax_by_customer',
    subtitleKey: 'reports.tax_by_customer_desc',
    route: '/reports/sales/tax-by-customer',
    sectionKey: 'reports.sales_reports',
    searchKeyKeys: ['reports.sales_other_reports'],
    showInOverview: false,
  ),
  _ReportEntry(
    icon: LucideIcons.fileSpreadsheet,
    titleKey: 'reports.sales_excel',
    subtitleKey: 'reports.sales_excel_desc',
    route: '/reports/sales/excel',
    sectionKey: 'reports.sales_reports',
    searchKeyKeys: ['reports.sales_export'],
    showInOverview: false,
  ),
  _ReportEntry(
    icon: LucideIcons.fileSpreadsheet,
    titleKey: 'reports.sales_excel_products',
    subtitleKey: 'reports.sales_excel_products_desc',
    route: '/reports/sales/excel-products',
    sectionKey: 'reports.sales_reports',
    searchKeyKeys: ['reports.sales_export'],
    showInOverview: false,
  ),

  // ── Purchase Reports ──
  _ReportEntry(
    icon: LucideIcons.shoppingBag,
    titleKey: 'reports.purchase_reports',
    subtitleKey: 'reports.purchase_reports_desc',
    route: '/reports/purchases',
    sectionKey: 'reports.purchase_reports',
  ),
  _ReportEntry(
    icon: LucideIcons.calendarDays,
    titleKey: 'reports.purchases_report',
    subtitleKey: 'reports.purchases_report_desc',
    route: '/reports/purchases/all',
    sectionKey: 'reports.purchase_reports',
    searchKeyKeys: ['reports.purchase_period_reports'],
    showInOverview: false,
  ),
  _ReportEntry(
    icon: LucideIcons.banknote,
    titleKey: 'reports.cash_purchases',
    subtitleKey: 'reports.cash_purchases_desc',
    route: '/reports/purchases/cash',
    sectionKey: 'reports.purchase_reports',
    searchKeyKeys: ['reports.purchase_period_reports'],
    showInOverview: false,
  ),
  _ReportEntry(
    icon: LucideIcons.clock,
    titleKey: 'reports.credit_purchases',
    subtitleKey: 'reports.credit_purchases_desc',
    route: '/reports/purchases/credit',
    sectionKey: 'reports.purchase_reports',
    searchKeyKeys: ['reports.purchase_period_reports'],
    showInOverview: false,
  ),
  _ReportEntry(
    icon: LucideIcons.creditCard,
    titleKey: 'reports.card_purchases',
    subtitleKey: 'reports.card_purchases_desc',
    route: '/reports/purchases/card',
    sectionKey: 'reports.purchase_reports',
    searchKeyKeys: ['reports.purchase_period_reports'],
    showInOverview: false,
  ),
  _ReportEntry(
    icon: LucideIcons.fileText,
    titleKey: 'reports.cheque_purchases',
    subtitleKey: 'reports.cheque_purchases_desc',
    route: '/reports/purchases/cheque',
    sectionKey: 'reports.purchase_reports',
    searchKeyKeys: ['reports.purchase_period_reports'],
    showInOverview: false,
  ),
  _ReportEntry(
    icon: LucideIcons.package2,
    titleKey: 'reports.purchases_by_product',
    subtitleKey: 'reports.purchases_by_product_desc',
    route: '/reports/purchases/by-product',
    sectionKey: 'reports.purchase_reports',
    searchKeyKeys: ['reports.purchase_product_reports'],
    showInOverview: false,
  ),
  _ReportEntry(
    icon: LucideIcons.folderOpen,
    titleKey: 'reports.purchases_by_category',
    subtitleKey: 'reports.purchases_by_category_desc',
    route: '/reports/purchases/by-category',
    sectionKey: 'reports.purchase_reports',
    searchKeyKeys: ['reports.purchase_product_reports'],
    showInOverview: false,
  ),
  _ReportEntry(
    icon: LucideIcons.truck,
    titleKey: 'reports.purchases_by_supplier',
    subtitleKey: 'reports.purchases_by_supplier_desc',
    route: '/reports/purchases/by-supplier',
    sectionKey: 'reports.purchase_reports',
    searchKeyKeys: ['reports.purchase_supplier_reports'],
    showInOverview: false,
  ),
  _ReportEntry(
    icon: LucideIcons.ban,
    titleKey: 'reports.cancelled_purchases',
    subtitleKey: 'reports.cancelled_purchases_desc',
    route: '/reports/purchases/cancelled',
    sectionKey: 'reports.purchase_reports',
    searchKeyKeys: ['reports.purchase_other_reports'],
    showInOverview: false,
  ),
  _ReportEntry(
    icon: LucideIcons.clipboardList,
    titleKey: 'reports.purchase_orders',
    subtitleKey: 'reports.purchase_orders_desc',
    route: '/reports/purchases/orders',
    sectionKey: 'reports.purchase_reports',
    searchKeyKeys: ['reports.purchase_other_reports'],
    showInOverview: false,
  ),
  _ReportEntry(
    icon: LucideIcons.fileSpreadsheet,
    titleKey: 'reports.purchases_excel',
    subtitleKey: 'reports.purchases_excel_desc',
    route: '/reports/purchases/excel',
    sectionKey: 'reports.purchase_reports',
    searchKeyKeys: ['reports.purchase_export'],
    showInOverview: false,
  ),
  _ReportEntry(
    icon: LucideIcons.fileSpreadsheet,
    titleKey: 'reports.purchases_excel_products',
    subtitleKey: 'reports.purchases_excel_products_desc',
    route: '/reports/purchases/excel-products',
    sectionKey: 'reports.purchase_reports',
    searchKeyKeys: ['reports.purchase_export'],
    showInOverview: false,
  ),

  // ── Discount Reports ──
  _ReportEntry(
    icon: LucideIcons.tag,
    titleKey: 'reports.discount_reports',
    subtitleKey: 'reports.discount_reports_desc',
    route: '/reports/discounts',
    sectionKey: 'reports.discount_reports',
  ),
  _ReportEntry(
    icon: LucideIcons.package2,
    titleKey: 'reports.discount_by_product',
    subtitleKey: 'reports.discount_by_product_desc',
    route: '/reports/discounts/by-product',
    sectionKey: 'reports.discount_reports',
    searchKeyKeys: ['reports.discount_breakdown'],
    showInOverview: false,
  ),
  _ReportEntry(
    icon: LucideIcons.layoutGrid,
    titleKey: 'reports.discount_by_category',
    subtitleKey: 'reports.discount_by_category_desc',
    route: '/reports/discounts/by-category',
    sectionKey: 'reports.discount_reports',
    searchKeyKeys: ['reports.discount_breakdown'],
    showInOverview: false,
  ),
  _ReportEntry(
    icon: LucideIcons.users,
    titleKey: 'reports.discount_by_customer',
    subtitleKey: 'reports.discount_by_customer_desc',
    route: '/reports/discounts/by-customer',
    sectionKey: 'reports.discount_reports',
    searchKeyKeys: ['reports.discount_breakdown'],
    showInOverview: false,
  ),
  _ReportEntry(
    icon: LucideIcons.receipt,
    titleKey: 'reports.discount_by_invoice',
    subtitleKey: 'reports.discount_by_invoice_desc',
    route: '/reports/discounts/by-invoice',
    sectionKey: 'reports.discount_reports',
    searchKeyKeys: ['reports.discount_breakdown'],
    showInOverview: false,
  ),
  _ReportEntry(
    icon: LucideIcons.badgePercent,
    titleKey: 'promotions.report.title',
    subtitleKey: 'promotions.report.subtitle',
    route: '/reports/promotions',
    sectionKey: 'reports.discount_reports',
  ),

  // ── Profit Reports ──
  _ReportEntry(
    icon: LucideIcons.trendingUp,
    titleKey: 'reports.profit_reports',
    subtitleKey: 'reports.profit_reports_desc',
    route: '/reports/profits',
    sectionKey: 'reports.profit_reports',
  ),
  _ReportEntry(
    icon: LucideIcons.trendingUp,
    titleKey: 'reports.profit_overall',
    subtitleKey: 'reports.profit_overall_desc',
    route: '/reports/profits/overall',
    sectionKey: 'reports.profit_reports',
    searchKeyKeys: ['reports.profit_overview'],
    showInOverview: false,
  ),
  _ReportEntry(
    icon: LucideIcons.receipt,
    titleKey: 'reports.profit_by_invoice',
    subtitleKey: 'reports.profit_by_invoice_desc',
    route: '/reports/profits/by-invoice',
    sectionKey: 'reports.profit_reports',
    searchKeyKeys: ['reports.profit_overview'],
    showInOverview: false,
  ),
  _ReportEntry(
    icon: LucideIcons.package2,
    titleKey: 'reports.profit_by_product',
    subtitleKey: 'reports.profit_by_product_desc',
    route: '/reports/profits/by-product',
    sectionKey: 'reports.profit_reports',
    searchKeyKeys: ['reports.profit_breakdown'],
    showInOverview: false,
  ),
  _ReportEntry(
    icon: LucideIcons.layoutGrid,
    titleKey: 'reports.profit_by_category',
    subtitleKey: 'reports.profit_by_category_desc',
    route: '/reports/profits/by-category',
    sectionKey: 'reports.profit_reports',
    searchKeyKeys: ['reports.profit_breakdown'],
    showInOverview: false,
  ),
  _ReportEntry(
    icon: LucideIcons.users,
    titleKey: 'reports.profit_by_customer',
    subtitleKey: 'reports.profit_by_customer_desc',
    route: '/reports/profits/by-customer',
    sectionKey: 'reports.profit_reports',
    searchKeyKeys: ['reports.profit_breakdown'],
    showInOverview: false,
  ),

  // ── Financial Reports (linked from Financial Management) ──
  _ReportEntry(
    icon: LucideIcons.scale,
    titleKey: 'financial_management.trial_balance',
    subtitleKey: 'financial_management.trial_balance_desc',
    route: '/reports/trial-balance',
    sectionKey: 'financial_management.financial_reports',
    showInOverview: false,
  ),
  _ReportEntry(
    icon: LucideIcons.trendingUp,
    titleKey: 'financial_management.profit_loss',
    subtitleKey: 'financial_management.profit_loss_desc',
    route: '/reports/profit-loss',
    sectionKey: 'financial_management.financial_reports',
    showInOverview: false,
  ),
  _ReportEntry(
    icon: LucideIcons.building2,
    titleKey: 'financial_management.balance_sheet',
    subtitleKey: 'financial_management.balance_sheet_desc',
    route: '/reports/balance-sheet',
    sectionKey: 'financial_management.financial_reports',
    showInOverview: false,
  ),
  _ReportEntry(
    icon: LucideIcons.bookOpenCheck,
    titleKey: 'financial_management.general_ledger',
    subtitleKey: 'financial_management.general_ledger_desc',
    route: '/reports/general-ledger',
    sectionKey: 'financial_management.financial_reports',
    showInOverview: false,
  ),

  // ── Inventory Reports ──
  _ReportEntry(
    icon: LucideIcons.warehouse,
    titleKey: 'reports.inventory_reports',
    subtitleKey: 'reports.inventory_reports_desc',
    route: '/reports/inventory',
    sectionKey: 'reports.inventory_reports',
  ),
  _ReportEntry(
    icon: LucideIcons.gitBranch,
    titleKey: 'reports.product_movement_detail',
    subtitleKey: 'reports.product_movement_detail_desc',
    route: '/reports/product-movement-detail',
    sectionKey: 'reports.inventory_reports',
  ),
  _ReportEntry(
    icon: LucideIcons.layers,
    titleKey: 'reports.variant_movement_report',
    subtitleKey: 'reports.variant_movement_report_desc',
    route: '/reports/product-variant-movement',
    sectionKey: 'reports.inventory_reports',
  ),
  _ReportEntry(
    icon: LucideIcons.folderOpen,
    titleKey: 'reports.category_movement_report',
    subtitleKey: 'reports.category_movement_report_desc',
    route: '/reports/category-movement',
    sectionKey: 'reports.inventory_reports',
  ),
  _ReportEntry(
    icon: LucideIcons.calendarClock,
    titleKey: 'reports.expiry_report_title',
    subtitleKey: 'reports.expiry_report_subtitle',
    route: '/reports/expiry',
    sectionKey: 'reports.inventory_reports',
  ),
  _ReportEntry(
    icon: LucideIcons.package,
    titleKey: 'batch_management.title',
    subtitleKey: 'batch_management.subtitle',
    route: '/reports/batches',
    sectionKey: 'reports.inventory_reports',
  ),
  _ReportEntry(
    icon: LucideIcons.arrowLeftRight,
    titleKey: 'reports.stock_movement_report',
    subtitleKey: 'reports.stock_movement_report_desc',
    route: '/reports/stock-movement',
    sectionKey: 'reports.inventory_reports',
  ),

  // ── Customer Reports ──
  _ReportEntry(
    icon: LucideIcons.users,
    titleKey: 'reports.customer_reports',
    subtitleKey: 'reports.customer_reports_desc',
    route: '/reports/customers',
    sectionKey: 'reports.customer_reports',
  ),
  _ReportEntry(
    icon: LucideIcons.undo2,
    titleKey: 'reports.customer_returns',
    subtitleKey: 'reports.customer_returns_desc',
    route: '/reports/customer-returns',
    sectionKey: 'reports.customer_reports',
  ),
  _ReportEntry(
    icon: LucideIcons.trophy,
    titleKey: 'reports.top_customers',
    subtitleKey: 'reports.top_customers_desc',
    route: '/reports/top-customers',
    sectionKey: 'reports.customer_reports',
  ),
  _ReportEntry(
    icon: LucideIcons.banknote,
    titleKey: 'reports.customer_payments',
    subtitleKey: 'reports.customer_payments_desc',
    route: '/reports/customer-payments',
    sectionKey: 'reports.customer_reports',
  ),
  _ReportEntry(
    icon: LucideIcons.shoppingCart,
    titleKey: 'reports.customer_sales',
    subtitleKey: 'reports.customer_sales_desc',
    route: '/reports/customer-sales',
    sectionKey: 'reports.customer_reports',
  ),
  _ReportEntry(
    icon: LucideIcons.clock,
    titleKey: 'reports.customer_aging_report',
    subtitleKey: 'reports.customer_aging_report_desc',
    route: '/reports/customer-aging',
    sectionKey: 'reports.customer_reports',
  ),
  _ReportEntry(
    icon: LucideIcons.fileText,
    titleKey: 'reports.customer_statement_report',
    subtitleKey: 'reports.customer_statement_report_desc',
    route: '/reports/customer-statement',
    sectionKey: 'reports.customer_reports',
  ),
  _ReportEntry(
    icon: LucideIcons.barChart3,
    titleKey: 'reports.customer_analysis',
    subtitleKey: 'reports.customer_analysis_desc',
    route: '/reports/customer-analysis',
    sectionKey: 'reports.customer_reports',
  ),
  _ReportEntry(
    icon: LucideIcons.bookOpen,
    titleKey: 'reports.customer_ledger_report',
    subtitleKey: 'reports.customer_ledger_report_desc',
    route: '/reports/customer-ledger',
    sectionKey: 'reports.customer_reports',
  ),
  _ReportEntry(
    icon: LucideIcons.receipt,
    titleKey: 'reports.customer_invoices_report',
    subtitleKey: 'reports.customer_invoices_report_desc',
    route: '/reports/customer-invoices',
    sectionKey: 'reports.customer_reports',
  ),

  // ── Supplier Reports ──
  _ReportEntry(
    icon: LucideIcons.truck,
    titleKey: 'reports.supplier_balance',
    subtitleKey: 'reports.supplier_balance_desc',
    route: '/reports/supplier-balance',
    sectionKey: 'reports.supplier_reports',
  ),
  _ReportEntry(
    icon: LucideIcons.arrowUpRight,
    titleKey: 'reports.supplier_debit_balance',
    subtitleKey: 'reports.supplier_debit_balance_desc',
    route: '/reports/supplier-debit-balance',
    sectionKey: 'reports.supplier_reports',
  ),
  _ReportEntry(
    icon: LucideIcons.arrowDownLeft,
    titleKey: 'reports.supplier_credit_balance',
    subtitleKey: 'reports.supplier_credit_balance_desc',
    route: '/reports/supplier-credit-balance',
    sectionKey: 'reports.supplier_reports',
  ),
  _ReportEntry(
    icon: LucideIcons.barChart3,
    titleKey: 'reports.supplier_analysis',
    subtitleKey: 'reports.supplier_analysis_desc',
    route: '/reports/supplier-analysis',
    sectionKey: 'reports.supplier_reports',
  ),
  _ReportEntry(
    icon: LucideIcons.clock,
    titleKey: 'reports.supplier_aging_report',
    subtitleKey: 'reports.supplier_aging_report_desc',
    route: '/reports/supplier-aging',
    sectionKey: 'reports.supplier_reports',
  ),
  _ReportEntry(
    icon: LucideIcons.fileText,
    titleKey: 'reports.supplier_statement_report',
    subtitleKey: 'reports.supplier_statement_report_desc',
    route: '/reports/supplier-statement',
    sectionKey: 'reports.supplier_reports',
  ),
  _ReportEntry(
    icon: LucideIcons.bookOpen,
    titleKey: 'reports.supplier_ledger_report',
    subtitleKey: 'reports.supplier_ledger_report_desc',
    route: '/reports/supplier-ledger',
    sectionKey: 'reports.supplier_reports',
  ),
  _ReportEntry(
    icon: LucideIcons.receipt,
    titleKey: 'reports.supplier_invoices_report',
    subtitleKey: 'reports.supplier_invoices_report_desc',
    route: '/reports/supplier-invoices',
    sectionKey: 'reports.supplier_reports',
  ),
  _ReportEntry(
    icon: LucideIcons.undo2,
    titleKey: 'reports.supplier_returns_report',
    subtitleKey: 'reports.supplier_returns_report_desc',
    route: '/reports/supplier-returns',
    sectionKey: 'reports.supplier_reports',
  ),
  _ReportEntry(
    icon: LucideIcons.warehouse,
    titleKey: 'reports.supplier_stocktake',
    subtitleKey: 'reports.supplier_stocktake_desc',
    route: '/reports/supplier-stocktake',
    sectionKey: 'reports.supplier_reports',
  ),
  _ReportEntry(
    icon: LucideIcons.searchCode,
    titleKey: 'reports.supplier_balance_drilldown',
    subtitleKey: 'reports.supplier_balance_drilldown_desc',
    route: '/reports/supplier-balance-drilldown',
    sectionKey: 'reports.supplier_reports',
  ),

  // ── Tax Reports ──
  _ReportEntry(
    icon: LucideIcons.receipt,
    titleKey: 'reports.sales_tax_report',
    subtitleKey: 'reports.sales_tax_report_desc',
    route: '/reports/sales-tax',
    sectionKey: 'reports.tax_reports',
  ),
  _ReportEntry(
    icon: LucideIcons.fileInput,
    titleKey: 'reports.purchase_tax_report',
    subtitleKey: 'reports.purchase_tax_report_desc',
    route: '/reports/purchase-tax',
    sectionKey: 'reports.tax_reports',
  ),

  // ── Salespeople Reports ──
  _ReportEntry(
    icon: LucideIcons.userCheck,
    titleKey: 'reports.salespeople_commission',
    subtitleKey: 'reports.salespeople_commission_desc',
    route: '/reports/salespeople-commission',
    sectionKey: 'reports.salespeople_reports',
  ),

  // ── Expense Reports ──
  _ReportEntry(
    icon: LucideIcons.receipt,
    titleKey: 'reports.expense_report',
    subtitleKey: 'reports.expense_report_desc',
    route: '/reports/expense-report',
    sectionKey: 'reports.expense_reports',
  ),

  // ── Cheque & Advance Reports ──
  _ReportEntry(
    icon: LucideIcons
        .wallet, // Closest equivalent to HugeIcons.strokeRoundedMoney01 / Invoice03
    titleKey: 'reports.unapplied_advances_report',
    subtitleKey: 'reports.unapplied_advances_report_desc',
    route: '/reports/unapplied-advances',
    sectionKey: 'reports.cheque_reports',
  ),

  // ── Diagnostics ──
  _ReportEntry(
    icon: Icons.health_and_safety,
    titleKey: 'reports.reconciliation',
    subtitleKey: 'reports.reconciliation_desc',
    route: '/reports/health',
    sectionKey: 'reports.diagnostics',
  ),
];

class _ReportsHubView extends StatefulWidget {
  const _ReportsHubView();

  @override
  State<_ReportsHubView> createState() => _ReportsHubViewState();
}

class _ReportsHubViewState extends State<_ReportsHubView> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Searches all user-facing metadata, including nested section headings.
  bool _matches(_ReportEntry entry) {
    if (_query.isEmpty) return true;
    final searchableText = <String>[
      entry.titleKey,
      entry.subtitleKey,
      entry.sectionKey,
      ...entry.searchKeyKeys,
    ].map((key) => key.tr().toLowerCase()).join(' ');
    return searchableText.contains(_query);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSearching = _query.isNotEmpty;

    // Nested entries stay hidden in the overview, but become direct searchable
    // destinations as soon as the user types a query.
    final filtered = _kAllReports
        .where((entry) => isSearching || entry.showInOverview)
        .where(_matches)
        .toList(growable: false);
    final grouped = <String, List<_ReportEntry>>{};
    for (final entry in filtered) {
      grouped.putIfAbsent(entry.sectionKey, () => []).add(entry);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('reports.title'.tr()),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.settings),
            onPressed: () => context.push('/settings'),
            tooltip: 'settings.title'.tr(),
          ),
        ],
      ),
      body: BlocBuilder<ReportsBloc, RealtimeState<ReportsData>>(
        builder: (context, state) {
          return Column(
            children: [
              // ── Search bar ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'reports.search_reports'.tr(),
                    prefixIcon: const Icon(LucideIcons.search),
                    suffixIcon: isSearching
                        ? IconButton(
                            icon: const Icon(LucideIcons.x, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest.withAlpha(
                      80,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                  onChanged: (value) =>
                      setState(() => _query = value.trim().toLowerCase()),
                ),
              ),
              // ── Report list ──
              Expanded(
                child: filtered.isEmpty
                    ? ReportScrollableCenter(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                LucideIcons.searchX,
                                size: 48,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'reports.no_search_results'.tr(),
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          // Health check banner — only when not searching
                          if (!isSearching) ...[
                            _buildHealthBanner(
                              context,
                              state,
                              theme,
                              colorScheme,
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Sections in original order
                          for (final sectionKey in _kSectionOrder)
                            if (grouped.containsKey(sectionKey)) ...[
                              _SectionHeader(title: sectionKey.tr()),
                              const SizedBox(height: 8),
                              for (final entry in grouped[sectionKey]!)
                                _ReportTile(
                                  icon: entry.icon,
                                  title: entry.titleKey.tr(),
                                  subtitle: entry.subtitleKey.tr(),
                                  onTap: () => context.push(entry.route),
                                  highlight: _query,
                                ),
                              const SizedBox(height: 24),
                            ],
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHealthBanner(
    BuildContext context,
    RealtimeState<ReportsData> state,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    if (state is RealtimeLoading<ReportsData>) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text('reports.checking_health'.tr()),
            ],
          ),
        ),
      );
    }

    if (state is RealtimeSuccess<ReportsData>) {
      final data = state.data;
      final healthy = data.isHealthy;
      return Card(
        color: healthy
            ? colorScheme.primaryContainer
            : colorScheme.errorContainer,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.push('/reports/health'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  healthy ? Icons.check_circle : Icons.warning,
                  color: healthy ? colorScheme.primary : colorScheme.error,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        healthy
                            ? 'reports.system_healthy'.tr()
                            : 'reports.issues_found'.tr(
                                args: ['${data.issueCount}'],
                              ),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'reports.tap_for_details'.tr(),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
    );
  }
}

class _ReportTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String highlight;

  const _ReportTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlight = '',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: highlight.isEmpty
            ? Text(title)
            : _HighlightedText(text: title, query: highlight, theme: theme),
        subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

/// Highlights matching portions of the report title during search.
class _HighlightedText extends StatelessWidget {
  final String text;
  final String query;
  final ThemeData theme;

  const _HighlightedText({
    required this.text,
    required this.query,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) return Text(text);

    final lower = text.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;

    while (true) {
      final index = lower.indexOf(query, start);
      if (index == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }
      spans.add(
        TextSpan(
          text: text.substring(index, index + query.length),
          style: TextStyle(
            backgroundColor: theme.colorScheme.primaryContainer,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
      start = index + query.length;
    }

    return RichText(
      text: TextSpan(style: theme.textTheme.bodyLarge, children: spans),
    );
  }
}
