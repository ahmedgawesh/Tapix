import 'package:easy_localization/easy_localization.dart';

typedef JournalDescriptionResolver =
    String Function(String key, List<String> args);

/// Localizes the stable, English audit descriptions stored on journal entries.
///
/// The stored text remains unchanged for audit/export purposes. Only the UI
/// representation is translated. Unknown or user-entered text is preserved.
String localizedJournalDescription(
  String? description, {
  JournalDescriptionResolver? resolver,
}) {
  final text = description?.trim() ?? '';
  final resolve =
      resolver ?? (key, args) => key.tr(args: args, namedArgs: const {});
  if (text.isEmpty) {
    return resolve('financial_management.transaction_line', const []);
  }
  return _localizeDescription(text, resolve);
}

String _localizeDescription(String text, JournalDescriptionResolver resolve) {
  const reversalPrefix = 'REVERSAL:';
  if (text.toUpperCase().startsWith(reversalPrefix)) {
    final original = text.substring(reversalPrefix.length).trim();
    return resolve('journal_descriptions.reversal', [
      _localizeDescription(original, resolve),
    ]);
  }

  const voidPrefix = 'VOID:';
  if (text.toUpperCase().startsWith(voidPrefix)) {
    final original = text.substring(voidPrefix.length).trim();
    return resolve('journal_descriptions.voided', [
      _localizeDescription(original, resolve),
    ]);
  }

  return text
      .split(' — ')
      .map((segment) => _localizeSegment(segment.trim(), resolve))
      .join(' — ');
}

String _localizeSegment(String segment, JournalDescriptionResolver resolve) {
  const exactKeys = <String, String>{
    'Cash': 'cash',
    'Bank': 'bank',
    'Cheque': 'cheque',
    'Credit': 'credit',
    'Cash + VAT': 'cash_vat',
    'Credit + VAT': 'credit_vat',
    'Cash Revenue': 'cash_revenue',
    'Credit Revenue': 'credit_revenue',
    'Cash Revenue + VAT': 'cash_revenue_vat',
    'Credit Revenue + VAT': 'credit_revenue_vat',
    'Cost of Goods Sold': 'cost_of_goods_sold',
    'COGS Reversal': 'cogs_reversal',
    'Sales return (contra-revenue)': 'sales_return_contra_revenue',
    'Purchase return (contra-COGS)': 'purchase_return_contra_cogs',
    'Output VAT reversed': 'output_vat_reversed',
    'Input VAT reversed': 'input_vat_reversed',
    'AR reduced': 'ar_reduced',
    'AP reduced': 'ap_reduced',
    'Inventory restored': 'inventory_restored',
    'Inventory decreased': 'inventory_decreased',
    'Inventory decreased (goods left premises)':
        'inventory_decreased_goods_left',
    'Inventory cost removed (offsets purchase return)':
        'inventory_cost_removed',
    'Inventory shrinkage (damaged/scrap)': 'inventory_shrinkage_damaged',
    'COGS reversed': 'cogs_reversed',
    'COGS reversed (write-off)': 'cogs_reversed_write_off',
    'Cash refund': 'cash_refund',
    'Bank refund': 'bank_refund',
    'Cheque refund': 'cheque_refund',
    'Customer credit issued': 'customer_credit_issued',
    'Cash refund received': 'cash_refund_received',
    'Bank refund received': 'bank_refund_received',
    'Cheque refund received': 'cheque_refund_received',
    'Purchase Return Adjustment income': 'purchase_return_adjustment_income',
    'Sales return adjustment expense': 'sales_return_adjustment_expense',
    'Opening Balance': 'opening_balance',
    'Opening balance': 'opening_balance',
    'Salary Payment': 'salary_payment',
    'Loyalty Points Earned': 'loyalty_points_earned',
    'Loyalty Points Redeemed': 'loyalty_points_redeemed',
    'Overpayment (customer prepayment)': 'customer_overpayment',
    'Cost Adjustment': 'cost_adjustment',
    'VAT Reversal': 'vat_reversal',
  };
  final exactKey = exactKeys[segment];
  if (exactKey != null) {
    return resolve('journal_descriptions.$exactKey', const []);
  }

  final parenthesizedReturn = RegExp(
    r'^(Sale|Purchase) Return #(\d+) \((.+)\)$',
  ).firstMatch(segment);
  if (parenthesizedReturn != null) {
    final reference = _reference(
      '${parenthesizedReturn.group(1)} Return #${parenthesizedReturn.group(2)}',
      resolve,
    );
    final method = _localizeSegment(parenthesizedReturn.group(3)!, resolve);
    return '$reference ($method)';
  }

  final fixedAsset = RegExp(r'^Fixed asset: (.+)$').firstMatch(segment);
  if (fixedAsset != null) {
    return resolve('journal_descriptions.fixed_asset', [fixedAsset.group(1)!]);
  }
  final depreciation = RegExp(
    r'^Depreciation (\d+)/(\d+)$',
  ).firstMatch(segment);
  if (depreciation != null) {
    return resolve('journal_descriptions.depreciation', [
      depreciation.group(1)!,
      depreciation.group(2)!,
    ]);
  }

  final revaluation = RegExp(
    r'^Inventory Revaluation #(\d+) \((up|down)\)$',
  ).firstMatch(segment);
  if (revaluation != null) {
    final direction = resolve(
      'journal_descriptions.revaluation_${revaluation.group(2)}',
      const [],
    );
    return resolve('journal_descriptions.inventory_revaluation', [
      revaluation.group(1)!,
      direction,
    ]);
  }

  final dishonouredResolution = RegExp(
    r'^Dishonoured cheque #(\d+) resolved by ([a-z_]+)$',
  ).firstMatch(segment);
  if (dishonouredResolution != null) {
    final method = resolve(
      'cheques.resolution_${dishonouredResolution.group(2)}',
      const [],
    );
    return resolve('journal_descriptions.cheque_dishonour_resolved', [
      dishonouredResolution.group(1)!,
      method,
    ]);
  }

  final reference = _reference(segment, resolve);
  if (reference != null) return reference;

  if (segment.contains(' + ')) {
    return segment
        .split(' + ')
        .map((part) => _localizeSegment(part.trim(), resolve))
        .join(' + ');
  }
  return segment;
}

String? _reference(String segment, JournalDescriptionResolver resolve) {
  const patterns = <(String, String)>[
    (r'^Incoming cheque #(\d+) cleared$', 'incoming_cheque_cleared'),
    (r'^Outgoing cheque #(\d+) cleared$', 'outgoing_cheque_cleared'),
    (
      r'^Incoming return cheque #(\d+) received$',
      'incoming_return_cheque_received',
    ),
    (
      r'^Outgoing return cheque #(\d+) issued$',
      'outgoing_return_cheque_issued',
    ),
    (
      r'^Incoming return cheque #(\d+) applied$',
      'incoming_return_cheque_applied',
    ),
    (
      r'^Outgoing return cheque #(\d+) applied$',
      'outgoing_return_cheque_applied',
    ),
    (
      r'^Return cheque #(\d+) deferred until clearance$',
      'return_cheque_deferred',
    ),
    (r'^Cheque #(\d+) cancelled$', 'cheque_cancelled'),
    (r'^Cheque #(\d+) dishonoured$', 'cheque_dishonoured'),
    (r'^Sale #(\d+)$', 'sale'),
    (r'^Purchase #(\d+)$', 'purchase'),
    (r'^Sale Return #(\d+)$', 'sale_return'),
    (r'^Purchase Return #(\d+)$', 'purchase_return'),
    (r'^Sale Adj Return #(\d+)$', 'sale_adjustment_return'),
    (r'^Purchase Adj Return #(\d+)$', 'purchase_adjustment_return'),
    (r'^Sale Adjustment Return #(\d+)$', 'sale_adjustment_return'),
    (r'^Purchase Adjustment Return #(\d+)$', 'purchase_adjustment_return'),
    (r'^Customer #(\d+)$', 'customer'),
    (r'^Supplier #(\d+)$', 'supplier'),
    (r'^Payroll #(\d+)$', 'payroll'),
    (r'^Redemption #(\d+)$', 'redemption'),
    (r'^Expense #(\d+)$', 'expense'),
    (r'^Customer Payment #(\d+)$', 'customer_payment'),
    (r'^Supplier Payment #(\d+)$', 'supplier_payment'),
    (r'^Direct Customer Payment #(\d+)$', 'direct_customer_payment'),
    (r'^Direct Supplier Payment #(\d+)$', 'direct_supplier_payment'),
    (r'^Customer Discount #(\d+)$', 'customer_discount'),
    (r'^Purchase Discount #(\d+)$', 'purchase_discount'),
    (r'^Commission Payment #(\d+)$', 'commission_payment'),
    (r'^Inventory Gain #(\d+)$', 'inventory_gain'),
    (r'^Inventory Shrinkage #(\d+)$', 'inventory_shrinkage'),
    (r'^Inventory Opening Balance #(\d+)$', 'inventory_opening_balance'),
  ];
  for (final (pattern, key) in patterns) {
    final match = RegExp(pattern).firstMatch(segment);
    if (match != null) {
      return resolve('journal_descriptions.$key', [match.group(1)!]);
    }
  }
  return null;
}
