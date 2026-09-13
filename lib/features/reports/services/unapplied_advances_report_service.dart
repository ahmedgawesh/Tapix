import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

enum UnappliedAdvancePartyFilter { all, customer, supplier }

class UnappliedAdvanceReportRow {
  final int accountPaymentId;
  final int chequeId;
  final String chequeNumber;
  final String partyType;
  final int partyId;
  final String partyName;
  final int amountCents;
  final int appliedCents;
  final int unappliedCents;
  final int currencyId;
  final String currencyCode;
  final String currencySymbol;
  final String status;
  final DateTime recognizedAt;

  const UnappliedAdvanceReportRow({
    required this.accountPaymentId,
    required this.chequeId,
    required this.chequeNumber,
    required this.partyType,
    required this.partyId,
    required this.partyName,
    required this.amountCents,
    required this.appliedCents,
    required this.unappliedCents,
    required this.currencyId,
    required this.currencyCode,
    required this.currencySymbol,
    required this.status,
    required this.recognizedAt,
  });
}

class UnappliedAdvanceCurrencySummary {
  final int currencyId;
  final String currencyCode;
  final String currencySymbol;
  final int customerCents;
  final int supplierCents;

  const UnappliedAdvanceCurrencySummary({
    required this.currencyId,
    required this.currencyCode,
    required this.currencySymbol,
    required this.customerCents,
    required this.supplierCents,
  });
}

class UnappliedAdvancesReportService {
  final AppDatabase _db;

  const UnappliedAdvancesReportService(this._db);

  Stream<List<UnappliedAdvanceReportRow>> watchRows() =>
      _query().watch().map((rows) => rows.map(_mapRow).toList(growable: false));

  Future<List<UnappliedAdvanceReportRow>> getRows() async =>
      (await _query().get()).map(_mapRow).toList(growable: false);

  List<UnappliedAdvanceCurrencySummary> summarize(
    Iterable<UnappliedAdvanceReportRow> rows,
  ) {
    final grouped = <int, _MutableSummary>{};
    for (final row in rows) {
      final summary = grouped.putIfAbsent(
        row.currencyId,
        () => _MutableSummary(row.currencyCode, row.currencySymbol),
      );
      if (row.partyType == 'customer') {
        summary.customerCents += row.unappliedCents;
      } else {
        summary.supplierCents += row.unappliedCents;
      }
    }
    final result = grouped.entries
        .map(
          (entry) => UnappliedAdvanceCurrencySummary(
            currencyId: entry.key,
            currencyCode: entry.value.code,
            currencySymbol: entry.value.symbol,
            customerCents: entry.value.customerCents,
            supplierCents: entry.value.supplierCents,
          ),
        )
        .toList();
    result.sort((a, b) => a.currencyCode.compareTo(b.currencyCode));
    return result;
  }

  Selectable<QueryRow> _query() => _db.customSelect(
    '''
      SELECT
        pap.id AS account_payment_id,
        pap.cheque_instrument_id AS cheque_id,
        COALESCE(NULLIF(ci.cheque_number, ''), '#' || ci.id) AS cheque_number,
        pap.party_type AS party_type,
        pap.party_id AS party_id,
        COALESCE(c.name, s.name, '#' || pap.party_id) AS party_name,
        pap.amount_cents AS amount_cents,
        pap.applied_cents AS applied_cents,
        pap.amount_cents - pap.applied_cents AS unapplied_cents,
        pap.currency_id AS currency_id,
        cur.code AS currency_code,
        cur.symbol AS currency_symbol,
        pap.status AS status,
        pap.recognized_at AS recognized_at
      FROM party_account_payments pap
      INNER JOIN cheque_instruments ci ON ci.id = pap.cheque_instrument_id
      INNER JOIN currencies cur ON cur.id = pap.currency_id
      LEFT JOIN customers c
        ON pap.party_type = 'customer' AND c.id = pap.party_id
      LEFT JOIN suppliers s
        ON pap.party_type = 'supplier' AND s.id = pap.party_id
      WHERE pap.status IN ('open', 'partially_applied')
        AND pap.amount_cents > pap.applied_cents
      ORDER BY pap.recognized_at DESC, pap.id DESC
    ''',
    readsFrom: {
      _db.partyAccountPayments,
      _db.chequeInstruments,
      _db.customers,
      _db.suppliers,
      _db.currencies,
    },
  );

  UnappliedAdvanceReportRow _mapRow(QueryRow row) => UnappliedAdvanceReportRow(
    accountPaymentId: row.read<int>('account_payment_id'),
    chequeId: row.read<int>('cheque_id'),
    chequeNumber: row.read<String>('cheque_number'),
    partyType: row.read<String>('party_type'),
    partyId: row.read<int>('party_id'),
    partyName: row.read<String>('party_name'),
    amountCents: row.read<int>('amount_cents'),
    appliedCents: row.read<int>('applied_cents'),
    unappliedCents: row.read<int>('unapplied_cents'),
    currencyId: row.read<int>('currency_id'),
    currencyCode: row.read<String>('currency_code'),
    currencySymbol: row.read<String>('currency_symbol'),
    status: row.read<String>('status'),
    recognizedAt: row.read<DateTime>('recognized_at'),
  );
}

class _MutableSummary {
  final String code;
  final String symbol;
  int customerCents = 0;
  int supplierCents = 0;

  _MutableSummary(this.code, this.symbol);
}
