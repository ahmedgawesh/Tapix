// ════════════════════════════════════════════════════════════════════════════
// SalespeopleCommissionReportBloc — commission attribution regression suite.
// ════════════════════════════════════════════════════════════════════════════
//
// Why this exists
// ---------------
// Field report (Jul 2026): the sales-rep commission report showed a
// salesperson's commission as a positive rate-based estimate while the
// employee-detail screen showed a NET commission that had gone negative
// after returns. Two root causes lived in `_loadSalespeopleCommission`:
//
//   1. Commission rows were attributed by the linked sale's `sale_date`
//      (via INNER JOIN), so a return-reversal was dragged back to the
//      ORIGINAL sale's month instead of landing in the return's month.
//      The employee-detail screen attributes by the row's own event date,
//      so the two screens disagreed.
//
//   2. The "use actual commission rows" branch only fired when the summed
//      commission was `> 0`. A net-negative (or zero) commission fell
//      through to the rate-based estimate `(sales * bps) / 10000`, masking
//      the real deducted amount with a fabricated positive number.
//
// This suite pins both fixes plus the world-class architecture that replaced
// the `created_at` heuristic: every commission row now carries an
// `effective_date` (the SAP / NetSuite / QuickBooks "posting / transaction
// date" — sale date for earned rows, return date for reversal rows). Reports
// attribute by `COALESCE(effective_date, created_at)`, so sales and returns
// land in their true economic period even for backdated documents, and the
// report reads correctly for any sub-month range.
// ════════════════════════════════════════════════════════════════════════════

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/features/reports/presentation/bloc/salespeople_commission_report_bloc.dart';
import 'package:tapix/features/reports/presentation/widgets/report_date_range.dart';

void main() {
  late AppDatabase db;
  late int currencyId;
  late int customerId;
  late int empId;

  // Report window: July 1–5, 2026 (mirrors the field-report screenshot).
  final rangeStart = DateTime(2026, 7, 1);
  final rangeEnd = DateTime(2026, 7, 5, 23, 59, 59);
  final julyDate = DateTime(2026, 7, 1, 10);
  final juneDate = DateTime(2026, 6, 15, 10);

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.customSelect('SELECT 1').get(); // force migrations + seeds
    await db.customStatement('PRAGMA foreign_keys = OFF');

    currencyId = (await db.select(db.currencies).get()).first.id;

    customerId = await db.into(db.customers).insert(
          CustomersCompanion.insert(name: 'Acme Co', currencyId: currencyId),
        );

    empId = await db.into(db.employees).insert(
          EmployeesCompanion.insert(
            name: 'bero',
            currencyId: currencyId,
            defaultCommissionRateBps: const Value(100), // 1%
          ),
        );
  });

  tearDown(() async => db.close());

  // ─── helpers ──────────────────────────────────────────────────────────

  Future<int> insertSale({
    required String invoice,
    required DateTime date,
    required int subtotalCents,
    required int totalCents,
  }) {
    return db.into(db.sales).insert(
          SalesCompanion.insert(
            invoiceNumber: invoice,
            customerId: Value(customerId),
            employeeId: Value(empId),
            currencyId: currencyId,
            subtotalCents: Decimal.fromInt(subtotalCents),
            taxCents: Decimal.fromInt(totalCents - subtotalCents),
            totalCents: Decimal.fromInt(totalCents),
            paymentMethod: 'cash',
            saleDate: Value(date),
            status: const Value('completed'),
          ),
        );
  }

  Future<void> insertCommission({
    required int saleId,
    required int amountCents,
    required DateTime createdAt,
    DateTime? effectiveDate,
  }) async {
    await db.into(db.commissions).insert(
          CommissionsCompanion.insert(
            employeeId: empId,
            saleId: Value(saleId),
            commissionRateBps: 100.0,
            commissionAmountCents: Decimal.fromInt(amountCents),
            currencyId: currencyId,
            effectiveDate: Value(effectiveDate),
            createdAt: Value(createdAt),
            status: const Value('pending'),
          ),
        );
  }

  /// Build the bloc, apply the fixed July 1–5 range, and return the first
  /// success payload.
  Future<SalespeopleCommissionReportData> loadReport() async {
    final bloc = SalespeopleCommissionReportBloc(db);
    addTearDown(bloc.close);
    bloc.add(SalespeopleCommissionReportDateRangeChanged(
      ReportDateRange(
        startDate: rangeStart,
        endDate: rangeEnd,
        preset: ReportPeriodPreset.custom,
      ),
    ));
    final state = await bloc.stream.firstWhere(
      (s) => s is RealtimeSuccess<SalespeopleCommissionReportData>,
    ) as RealtimeSuccess<SalespeopleCommissionReportData>;
    return state.data;
  }

  SalespersonCommissionItem beroOf(SalespeopleCommissionReportData data) =>
      data.salespeople.firstWhere((s) => s.employeeId == empId);

  // ─── tests ──────────────────────────────────────────────────────────────

  test('earned commission uses actual row, not tax-inclusive estimate', () async {
    // Sale total = 1060.50 (incl. 1% tax); commission earned on the
    // pre-tax subtotal 1050.00 → 10.50, NOT 1% of 1060.50 (= 10.605).
    final saleId = await insertSale(
      invoice: 'INV-1',
      date: julyDate,
      subtotalCents: 105000,
      totalCents: 106050,
    );
    await insertCommission(
        saleId: saleId, amountCents: 1050, createdAt: julyDate);

    final data = await loadReport();
    expect(beroOf(data).totalCommissionEarnedCents, 1050);
    expect(data.grandTotalCommissionCents, 1050);
  });

  test('net-negative commission is reported as-is, not masked by estimate',
      () async {
    // Earned 10.50, deducted 11.30 → net -0.80. The old `> 0` guard would
    // have fallen through to (1060.50 * 1%) ≈ 10.60.
    final saleId = await insertSale(
      invoice: 'INV-1',
      date: julyDate,
      subtotalCents: 105000,
      totalCents: 106050,
    );
    await insertCommission(
        saleId: saleId, amountCents: 1050, createdAt: julyDate);
    await insertCommission(
        saleId: saleId, amountCents: -1130, createdAt: julyDate);

    final data = await loadReport();
    expect(beroOf(data).totalCommissionEarnedCents, -80);
    expect(data.grandTotalCommissionCents, -80);
  });

  test('reversal is attributed by its own date, not the sale date', () async {
    // A June sale reversed in July: the reversal must land in the July
    // report even though its linked sale_date is in June.
    final julySale = await insertSale(
      invoice: 'INV-JUL',
      date: julyDate,
      subtotalCents: 105000,
      totalCents: 106050,
    );
    final juneSale = await insertSale(
      invoice: 'INV-JUN',
      date: juneDate,
      subtotalCents: 50000,
      totalCents: 50500,
    );
    // July earned +10.50
    await insertCommission(
        saleId: julySale, amountCents: 1050, createdAt: julyDate);
    // Reversal of the JUNE sale, but recorded in JULY → belongs to July.
    await insertCommission(
        saleId: juneSale, amountCents: -300, createdAt: julyDate);
    // June's original earned commission is dated in June → out of range.
    await insertCommission(
        saleId: juneSale, amountCents: 500, createdAt: juneDate);

    final data = await loadReport();
    // 1050 (July earned) - 300 (July-dated reversal) = 750.
    // The June-dated +500 earned row is excluded by the July window.
    expect(beroOf(data).totalCommissionEarnedCents, 750);
  });

  test('effective_date takes precedence over created_at (backdated document)',
      () async {
    // A reversal physically inserted in a LATER month (created_at) but whose
    // economic-event date (effective_date) falls inside the July window must
    // be attributed to July. This is the backdate-safe behaviour the raw
    // `created_at` filter could not provide.
    final saleId = await insertSale(
      invoice: 'INV-1',
      date: julyDate,
      subtotalCents: 105000,
      totalCents: 106050,
    );
    // Earned: effective July, created August (backdated entry).
    await insertCommission(
      saleId: saleId,
      amountCents: 1050,
      createdAt: DateTime(2026, 8, 20),
      effectiveDate: julyDate,
    );
    // A row whose effective_date is OUTSIDE July (August) must be excluded
    // even though it was created inside the July window.
    await insertCommission(
      saleId: saleId,
      amountCents: 999,
      createdAt: julyDate,
      effectiveDate: DateTime(2026, 8, 2),
    );

    final data = await loadReport();
    expect(beroOf(data).totalCommissionEarnedCents, 1050);
  });

  test('salesperson with commission rows but no in-range sale is excluded',
      () async {
    // Only a June sale exists; the July report lists salespeople by their
    // in-range sales, so bero should not appear at all.
    final juneSale = await insertSale(
      invoice: 'INV-JUN',
      date: juneDate,
      subtotalCents: 50000,
      totalCents: 50500,
    );
    await insertCommission(
        saleId: juneSale, amountCents: -300, createdAt: julyDate);

    final data = await loadReport();
    expect(data.salespeople.where((s) => s.employeeId == empId), isEmpty);
  });
}
