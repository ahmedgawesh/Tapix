import 'package:easy_localization/easy_localization.dart';

typedef PartyTransactionTextResolver =
    String Function(String key, List<String> args);

String localizedPartyTransactionType(
  String type, {
  PartyTransactionTextResolver? resolver,
}) {
  final resolve = resolver ?? (key, args) => key.tr(args: args);
  const suffixes = <String, String>{
    'sale': 'sale',
    'purchase': 'purchase',
    'sale_void': 'sale_void',
    'purchase_void': 'purchase_void',
    'payment': 'payment',
    'payment_reversal': 'payment_reversal',
    'discount': 'discount',
    'return': 'return',
    'sale_return': 'sale_return',
    'purchase_return': 'purchase_return',
    'refund': 'refund',
    'refund_reversal': 'refund_reversal',
    'adjustment': 'adjustment',
    'adjustment_return': 'adjustment_return',
    'adjustment_return_reversal': 'adjustment_return_reversal',
    'credit_note': 'credit_note',
    'credit_note_reversal': 'credit_note_reversal',
    'cheque_return_pending': 'cheque_return_pending',
    'cheque_return_pending_reversal': 'cheque_return_pending_reversal',
    'cheque_return_settlement': 'cheque_return_settlement',
    'cheque_return_settlement_reversal': 'cheque_return_settlement_reversal',
    'cheque_return_settlement_void': 'cheque_return_settlement_reversal',
    'return_settlement_cash': 'return_settlement_cash',
    'return_settlement_card': 'return_settlement_card',
    'return_settlement_bank_transfer': 'return_settlement_bank_transfer',
    'return_settlement_mobile': 'return_settlement_mobile',
    'return_settlement_void': 'return_settlement_void',
    'opening_balance': 'opening_balance',
    'earn': 'loyalty_earn',
    'redeem': 'loyalty_redeem',
  };
  final suffix = suffixes[type];
  return suffix == null ? type : resolve('reports.txn_type_$suffix', const []);
}

String localizedPartyTransactionDescription(
  String? description, {
  PartyTransactionTextResolver? resolver,
}) {
  final text = description?.trim() ?? '';
  if (text.isEmpty) return '';
  final resolve = resolver ?? (key, args) => key.tr(args: args);

  String? match(String pattern, String key, {int groups = 1}) {
    final result = RegExp(pattern, caseSensitive: false).firstMatch(text);
    if (result == null) return null;
    return resolve(
      'reports.txn_desc_$key',
      List<String>.generate(groups, (index) => result.group(index + 1) ?? ''),
    );
  }

  String localizedMethod(String raw) {
    final normalized = raw.trim().toLowerCase();
    const methods = <String, String>{
      'cash': 'cash',
      'card': 'card',
      'credit': 'credit',
      'cheque': 'cheque',
      'check': 'cheque',
      'bank': 'bank',
      'bank_transfer': 'bank',
      'mobile': 'mobile',
    };
    final suffix = methods[normalized];
    return suffix == null
        ? raw
        : resolve('reports.txn_method_$suffix', const []);
  }

  String? matchWithMethod(String pattern, String key) {
    final result = RegExp(pattern, caseSensitive: false).firstMatch(text);
    if (result == null) return null;
    return resolve('reports.txn_desc_$key', [
      result.group(1) ?? '',
      localizedMethod(result.group(2) ?? ''),
    ]);
  }

  String? matchReturnSettlement() {
    final result = RegExp(
      r'^(?:sale|purchase) return settlement \(([^)]+)\) for ([^#]+)#(\d+)(?: ·.*)?$',
      caseSensitive: false,
    ).firstMatch(text);
    if (result == null) return null;
    return resolve('reports.txn_desc_return_settlement', [
      '${result.group(2)}#${result.group(3)}',
      localizedMethod(result.group(1) ?? ''),
    ]);
  }

  String? matchAccountCheque() {
    final result = RegExp(
      r'^(Incoming|Outgoing) account cheque (.+?)(?: — (.+))?$',
      caseSensitive: false,
    ).firstMatch(text);
    if (result == null) return null;
    final direction = result.group(1)!.toLowerCase();
    final localized = resolve('reports.txn_desc_${direction}_account_cheque', [
      result.group(2) ?? '',
    ]);
    final note = result.group(3)?.trim();
    return note == null || note.isEmpty ? localized : '$localized — $note';
  }

  return matchAccountCheque() ??
      matchReturnSettlement() ??
      match(
        r'^Reversed payments for voided sale (.+)$',
        'reversed_payments_voided_sale',
      ) ??
      match(
        r'^Reversed payments for voided purchase (.+)$',
        'reversed_payments_voided_purchase',
      ) ??
      match(r'^Deleted payment for (.+)$', 'deleted_payment') ??
      match(r'^Payment for (.+?) \(backfilled\)$', 'payment_backfilled') ??
      match(
        r'^Payment for (.+?) \(cleared cheque (.*)\)$',
        'payment_cleared_cheque',
        groups: 2,
      ) ??
      match(
        r'^Payment for (.+?) \(received cheque (.*)\)$',
        'payment_received_cheque',
        groups: 2,
      ) ??
      match(
        r'^Payment for (.+?) \(issued cheque (.*)\)$',
        'payment_issued_cheque',
        groups: 2,
      ) ??
      match(r'^Incoming cheque for (.+)$', 'incoming_cheque_for') ??
      match(r'^Issued cheque for (.+)$', 'issued_cheque_for') ??
      match(
        r'^Incoming cheque (.+?) for (.+)$',
        'incoming_cheque_number_for',
        groups: 2,
      ) ??
      match(
        r'^Issued cheque (.+?) for (.+)$',
        'issued_cheque_number_for',
        groups: 2,
      ) ??
      match(
        r'^Outgoing return cheque (.+?) issued$',
        'outgoing_return_cheque_issued',
      ) ??
      match(
        r'^Incoming return cheque (.+?) received$',
        'incoming_return_cheque_received',
      ) ??
      match(
        r'^Outgoing return cheque (.+?) cleared(?: — .*)?$',
        'outgoing_return_cheque_cleared',
      ) ??
      match(
        r'^Incoming return cheque (.+?) cleared(?: — .*)?$',
        'incoming_return_cheque_cleared',
      ) ??
      match(
        r'^Return cheque #(.+?) settlement reversed(?: — .*)?$',
        'return_cheque_settlement_reversed',
      ) ??
      match(
        r'^Voided return cheque #(.+?) settlement$',
        'return_cheque_settlement_voided',
      ) ??
      match(r'^Payment for (.+)$', 'payment') ??
      match(r'^Voided sale return (.+)$', 'voided_sale_return') ??
      match(r'^Voided purchase return (.+)$', 'voided_purchase_return') ??
      match(
        r'^Voided Purchase Adjustment Return (.+)$',
        'voided_purchase_adjustment_return',
      ) ??
      match(
        r'^Purchase Adjustment Return (.+)$',
        'purchase_adjustment_return',
      ) ??
      matchWithMethod(
        r'^Void adjustment return (.+?) \((.+)\)$',
        'voided_sale_adjustment_return',
      ) ??
      matchWithMethod(
        r'^Adjustment sale return (.+?) \((.+)\)$',
        'sale_adjustment_return',
      ) ??
      matchWithMethod(r'^Sale return (.+?) \((.+)\)$', 'sale_return_method') ??
      matchWithMethod(
        r'^Purchase return (.+?) \((.+)\)$',
        'purchase_return_method',
      ) ??
      match(r'^Sale return (.+)$', 'sale_return') ??
      match(r'^Purchase return (.+)$', 'purchase_return') ??
      match(r'^Voided sale (.+)$', 'voided_sale') ??
      match(r'^Voided purchase (.+)$', 'voided_purchase') ??
      match(r'^Sale (.+)$', 'sale') ??
      match(r'^Purchase (.+?) \(backfilled\)$', 'purchase_backfilled') ??
      match(r'^Purchase (.+)$', 'purchase') ??
      match(r'^Excess cash added to balance . (.+)$', 'excess_cash_balance') ??
      text;
}
