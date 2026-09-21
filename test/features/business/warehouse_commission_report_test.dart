import 'dart:async';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/features/business/data/business_foundation_repository.dart';
import 'package:tapix/features/reports/presentation/bloc/salespeople_commission_report_bloc.dart';
import 'package:uuid/uuid.dart';
import 'business_foundation_test.dart' as fixtures;

void main() {
  late AppDatabase db;
  late int currency, employee;
  late String primary, remote, now;
  late Map<String, int> localDocs, remoteDocs;
  Future<int> insert(
    String table,
    Map<String, Object> values,
  ) => db.customInsert(
    'INSERT INTO $table (${values.keys.join(',')}) VALUES (${List.filled(values.length, '?').join(',')})',
    variables: values.values
        .map(
          (v) =>
              v is int ? Variable.withInt(v) : Variable.withString(v as String),
        )
        .toList(),
  );
  Future<int> commission(
    int amount, {
    int? sale,
    int? linked,
    int? adjustment,
    String status = 'pending',
    String? date,
  }) => insert('commissions', {
    'employee_id': employee,
    'currency_id': currency,
    'commission_rate_bps': 500,
    'commission_amount_cents': amount,
    'status': status,
    'effective_date': date ?? now,
    'sale_id': ?sale,
    'sale_return_id': ?linked,
    'sale_return_adjustment_id': ?adjustment,
  });
  Future<void> move(String table, int id, String warehouse) => db.customUpdate(
    'UPDATE business_document_locations SET warehouse_id = ? WHERE source_table = ? AND source_id = ?',
    variables: [
      Variable.withString(warehouse),
      Variable.withString(table),
      Variable.withInt(id),
    ],
    updates: {db.businessDocumentLocations},
  );
  Future<Map<String, int>> seed(
    String name,
    int revenue,
    int earned,
    int returned,
    int adjusted,
  ) async {
    final sale = await insert('sales', {
      'invoice_number': name,
      'currency_id': currency,
      'employee_id': employee,
      'subtotal_cents': revenue,
      'tax_cents': 0,
      'total_cents': revenue,
      'status': 'completed',
      'payment_method': 'cash',
      'sale_date': now,
    });
    final linked = await insert('sale_returns', {
      'sale_id': sale,
      'return_number': '$name-return',
      'currency_id': currency,
      'total_cents': 100,
      'return_date': now,
      'status': 'posted',
    });
    final adjustment = await insert('sale_return_adjustments', {
      'return_number': '$name-adjustment',
      'currency_id': currency,
      'total_cents': 100,
      'return_date': now,
      'status': 'posted',
    });
    await commission(
      earned,
      sale: sale,
      status: name == 'remote' ? 'paid' : 'pending',
    );
    await commission(-returned, sale: sale, linked: linked, status: 'approved');
    await commission(-adjusted, adjustment: adjustment);
    return {
      'sales': sale,
      'sale_returns': linked,
      'sale_return_adjustments': adjustment,
    };
  }

  setUp(() async {
    db = fixtures.memoryDb();
    currency = (await db.select(db.currencies).get()).first.id;
    employee = await insert('employees', {
      'name': 'Agent',
      'currency_id': currency,
    });
    now = DateTime.now().toIso8601String();
    final scope = await BusinessFoundationRepository(db).getScope();
    primary = scope.warehouseId;
    remote = const Uuid().v4();
    await db
        .into(db.businessWarehouses)
        .insert(
          BusinessWarehousesCompanion.insert(
            id: remote,
            organizationId: scope.organizationId,
            branchId: scope.branchId,
            code: 'OTHER',
          ),
        );
    await db.customStatement('DROP TRIGGER business_location_immutable');
    localDocs = await seed('local', 10000, 500, 100, 50);
    remoteDocs = await seed('remote', 20000, 1000, 200, 80);
    for (final doc in remoteDocs.entries) {
      await move(doc.key, doc.value, remote);
    }
  });
  tearDown(() => db.close());
  SalespeopleCommissionReportBloc bloc(CommissionReportScope scope) {
    final report = SalespeopleCommissionReportBloc(db, scope: scope);
    addTearDown(report.close);
    return report;
  }

  Future<SalespeopleCommissionReportData> local() =>
      bloc(CommissionReportScope.primaryWarehouse).dataStream.first;
  Future<SalespeopleCommissionReportData> account() =>
      bloc(CommissionReportScope.account).dataStream.first;

  test(
    'default account retains all sites and recorded event statuses',
    () async {
      final report = SalespeopleCommissionReportBloc(db);
      addTearDown(report.close);
      final data = await report.dataStream.first;
      expect(data.scope, CommissionReportScope.account);
      expect(data.grandTotalCommissionCents, 1070);
      expect(data.grandTotalSalesCents, 30000);
      expect(data.grandTotalPaidCents, 1000);
    },
  );
  test('primary scope includes only its three exact event sources', () async {
    final data = await local();
    expect(data.scope, CommissionReportScope.primaryWarehouse);
    expect(data.grandTotalCommissionCents, 350);
    expect(data.grandTotalSalesCents, 10000);
    expect(data.totalSalesCount, 1);
    expect(data.grandTotalPendingCents, 450);
    expect(data.salespeople.single.approvedCommissionCents, -100);
    expect(data.grandTotalPaidCents, 0);
    expect(data.copyWith().scope, data.scope);
  });
  test(
    'linked return follows its own location when original invoice moves',
    () async {
      await move('sales', localDocs['sales']!, remote);
      final data = await local();
      expect(data.totalSalesCount, 0);
      expect(data.grandTotalCommissionCents, -150);
      expect(data.totalSalespeople, 1);
    },
  );
  test(
    'foreign linked return is excluded even when invoice is local',
    () async {
      await move('sale_returns', localDocs['sale_returns']!, remote);
      expect((await local()).grandTotalCommissionCents, 450);
    },
  );
  test(
    'inactive warehouse and employee retain historical commissions',
    () async {
      await (db.update(db.businessWarehouses)
            ..where((w) => w.id.equals(primary)))
          .write(const BusinessWarehousesCompanion(isActive: Value(false)));
      await (db.update(db.employees)..where((e) => e.id.equals(employee)))
          .write(const EmployeesCompanion(isActive: Value(false)));
      expect((await local()).grandTotalCommissionCents, 350);
    },
  );
  for (final unknown in ['legacy_return', 'manual', 'missing_location']) {
    test(
      '$unknown blocks partial local totals but preserves full account',
      () async {
        final before = await fixtures.legacySnapshot(db);
        if (unknown == 'legacy_return') {
          await commission(-30, sale: localDocs['sales']);
        } else if (unknown == 'manual') {
          await commission(17);
        } else {
          await db.customStatement(
            'DROP TRIGGER business_location_sales_retain',
          );
          await db.customStatement(
            "DELETE FROM business_document_locations WHERE source_table = 'sales' AND source_id = ?",
            [localDocs['sales']],
          );
        }
        await expectLater(
          local(),
          throwsA(
            isA<UnresolvedCommissionSources>().having(
              (e) => e.count,
              'count',
              1,
            ),
          ),
        );
        expect(
          (await account()).grandTotalCommissionCents,
          unknown == 'legacy_return'
              ? 1040
              : unknown == 'manual'
              ? 1087
              : 1070,
        );
        if (unknown == 'missing_location') {
          expect(await fixtures.legacySnapshot(db), before);
        }
      },
    );
  }
  test(
    'unknown records outside the period do not block local history',
    () async {
      final date = DateTime.now();
      await commission(
        -30,
        sale: localDocs['sales'],
        date: DateTime(date.year, date.month - 1, 10).toIso8601String(),
      );
      expect((await local()).grandTotalCommissionCents, 350);
    },
  );
  test(
    'returns keep their event period when invoice date is outside it',
    () async {
      final date = DateTime.now();
      await db.customStatement('UPDATE sales SET sale_date = ?', [
        DateTime(date.year, date.month - 1, 10).toIso8601String(),
      ]);
      final data = await local();
      expect(data.totalSalesCount, 0);
      expect(data.grandTotalCommissionCents, 350);
    },
  );
  test('location-only changes refresh local report', () async {
    final stream = StreamIterator(
      bloc(CommissionReportScope.primaryWarehouse).dataStream,
    );
    addTearDown(stream.cancel);
    expect(await stream.moveNext(), isTrue);
    expect(stream.current.grandTotalCommissionCents, 350);
    await move(
      'sale_return_adjustments',
      localDocs['sale_return_adjustments']!,
      remote,
    );
    expect(await stream.moveNext().timeout(const Duration(seconds: 5)), isTrue);
    expect(stream.current.grandTotalCommissionCents, 400);
  });
  test(
    'source status changes invalidate the report instead of retaining stale totals',
    () async {
      final stream = StreamIterator(
        bloc(CommissionReportScope.primaryWarehouse).dataStream,
      );
      addTearDown(stream.cancel);
      await stream.moveNext();
      await (db.update(db.saleReturnAdjustments)
            ..where((r) => r.id.equals(localDocs['sale_return_adjustments']!)))
          .write(const SaleReturnAdjustmentsCompanion(status: Value('voided')));
      await expectLater(
        stream.moveNext(),
        throwsA(isA<UnresolvedCommissionSources>()),
      );
    },
  );
  test(
    'scope selection recovers from unresolved local report to full account',
    () async {
      await commission(-30, sale: localDocs['sales']);
      final report = bloc(CommissionReportScope.primaryWarehouse);
      await report.stream
          .firstWhere(
            (s) => s is RealtimeError<SalespeopleCommissionReportData>,
          )
          .timeout(const Duration(seconds: 5));
      final next = report.stream
          .firstWhere(
            (s) => s is RealtimeSuccess<SalespeopleCommissionReportData>,
          )
          .timeout(const Duration(seconds: 5));
      report.add(
        const SalespeopleCommissionReportScopeChanged(
          CommissionReportScope.account,
        ),
      );
      final data =
          (await next as RealtimeSuccess<SalespeopleCommissionReportData>).data;
      expect(data.scope, CommissionReportScope.account);
      expect(data.grandTotalCommissionCents, 1040);
    },
  );
  test(
    'sorting cannot restore stale account totals after local scope fails',
    () async {
      await commission(-30, sale: localDocs['sales']);
      final report = bloc(CommissionReportScope.account);
      await report.stream
          .firstWhere(
            (s) => s is RealtimeSuccess<SalespeopleCommissionReportData>,
          )
          .timeout(const Duration(seconds: 5));
      final error = report.stream
          .firstWhere(
            (s) => s is RealtimeError<SalespeopleCommissionReportData>,
          )
          .timeout(const Duration(seconds: 5));
      report.add(
        const SalespeopleCommissionReportScopeChanged(
          CommissionReportScope.primaryWarehouse,
        ),
      );
      await error;
      report.add(
        const SalespeopleCommissionReportSortChanged(
          SalespeopleCommissionSortType.nameAsc,
        ),
      );
      await pumpEventQueue();
      expect(
        report.state,
        isA<RealtimeError<SalespeopleCommissionReportData>>(),
      );
    },
  );
}
