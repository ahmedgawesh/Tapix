import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/features/reports/presentation/bloc/customer_reports_bloc.dart'
    as customer_reports;
import 'package:tapix/features/reports/presentation/widgets/report_date_range.dart';
import 'package:tapix/features/reports/services/party_aging_ledger_service.dart';

void main() {
  final asOf = DateTime(2026, 8, 8, 23, 59, 59);

  group('PartyAgingCalculator', () {
    test('applies every signed credit FIFO and fills all five buckets', () {
      final movements = <PartyAgingMovement>[
        PartyAgingMovement(
          id: 1,
          amountCents: 5000,
          transactionDate: asOf.subtract(const Duration(days: 100)),
        ),
        PartyAgingMovement(
          id: 2,
          amountCents: 4000,
          transactionDate: asOf.subtract(const Duration(days: 45)),
        ),
        PartyAgingMovement(
          id: 3,
          amountCents: 500,
          transactionDate: asOf.subtract(const Duration(days: 70)),
        ),
        PartyAgingMovement(
          id: 4,
          amountCents: 3000,
          transactionDate: asOf.subtract(const Duration(days: 10)),
        ),
        PartyAgingMovement(id: 5, amountCents: 2000, transactionDate: asOf),
        PartyAgingMovement(
          id: 6,
          amountCents: -7000,
          transactionDate: asOf.subtract(const Duration(days: 5)),
        ),
        PartyAgingMovement(
          id: 7,
          amountCents: -1000,
          transactionDate: asOf.subtract(const Duration(days: 2)),
        ),
        PartyAgingMovement(
          id: 8,
          amountCents: 9999,
          transactionDate: asOf.add(const Duration(days: 1)),
        ),
      ];

      final result = PartyAgingCalculator.calculate(
        openingBalanceCents: 10000,
        movements: movements,
        asOf: asOf,
      );

      expect(result.currentCents, 2000);
      expect(result.days30Cents, 3000);
      expect(result.days60Cents, 4000);
      expect(result.days90Cents, 500);
      expect(result.over90Cents, 7000);
      expect(result.totalCents, 16500);
    });

    test('bucket boundaries have no gaps or overlaps', () {
      final ages = <int>[0, 1, 30, 31, 60, 61, 90, 91];
      final movements = <PartyAgingMovement>[
        for (var i = 0; i < ages.length; i++)
          PartyAgingMovement(
            id: i + 1,
            amountCents: 100,
            transactionDate: asOf.subtract(Duration(days: ages[i])),
          ),
      ];

      final result = PartyAgingCalculator.calculate(
        openingBalanceCents: 0,
        movements: movements,
        asOf: asOf,
      );

      expect(result.currentCents, 100);
      expect(result.days30Cents, 200);
      expect(result.days60Cents, 200);
      expect(result.days90Cents, 200);
      expect(result.over90Cents, 100);
      expect(result.totalCents, 800);
    });
  });

  group('PartyAgingLedgerService and balance rebuild', () {
    late AppDatabase db;
    late int currencyId;

    setUp(() async {
      db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
      await db.customSelect('SELECT 1').get();
      currencyId = (await (db.select(
        db.currencies,
      )..where((c) => c.code.equals('USD'))).getSingle()).id;
    });

    tearDown(() => db.close());

    test(
      'customer aging is derived as-of and does not trust cached balance',
      () async {
        final customerId = await db
            .into(db.customers)
            .insert(
              CustomersCompanion.insert(
                name: 'Inactive but owing customer',
                currencyId: currencyId,
                openingBalanceCents: Value(Decimal.fromInt(10000)),
                balanceCents: Value(Decimal.fromInt(1)),
                isActive: const Value(false),
                createdAt: Value(asOf.subtract(const Duration(days: 200))),
              ),
            );

        final movements = <PartyAgingMovement>[
          PartyAgingMovement(
            id: 1,
            amountCents: 5000,
            transactionDate: asOf.subtract(const Duration(days: 100)),
          ),
          PartyAgingMovement(
            id: 2,
            amountCents: 4000,
            transactionDate: asOf.subtract(const Duration(days: 45)),
          ),
          PartyAgingMovement(
            id: 3,
            amountCents: 500,
            transactionDate: asOf.subtract(const Duration(days: 70)),
          ),
          PartyAgingMovement(
            id: 4,
            amountCents: 3000,
            transactionDate: asOf.subtract(const Duration(days: 10)),
          ),
          PartyAgingMovement(id: 5, amountCents: 2000, transactionDate: asOf),
          PartyAgingMovement(
            id: 6,
            amountCents: -7000,
            transactionDate: asOf.subtract(const Duration(days: 5)),
          ),
          PartyAgingMovement(
            id: 7,
            amountCents: -1000,
            transactionDate: asOf.subtract(const Duration(days: 2)),
          ),
          PartyAgingMovement(
            id: 8,
            amountCents: 9999,
            transactionDate: asOf.add(const Duration(days: 1)),
          ),
        ];
        for (final movement in movements) {
          await db
              .into(db.customerTransactions)
              .insert(
                CustomerTransactionsCompanion.insert(
                  customerId: customerId,
                  transactionType: movement.amountCents >= 0
                      ? 'adjustment'
                      : 'payment',
                  amountCents: Decimal.fromInt(movement.amountCents),
                  currencyId: currencyId,
                  transactionDate: Value(movement.transactionDate),
                ),
              );
        }

        final records = await PartyAgingLedgerService(
          db,
        ).loadCustomers(asOf: asOf);
        final record = records.single;
        expect(record.partyId, customerId);
        expect(record.buckets.totalCents, 16500);
        expect(record.buckets.days90Cents, 500);

        final bloc = customer_reports.CustomerReportsBloc(db);
        addTearDown(bloc.close);
        bloc.add(
          customer_reports.CustomerReportsDateRangeChanged(
            ReportDateRange(startDate: DateTime(2026, 1, 1), endDate: asOf),
          ),
        );
        final state =
            await bloc.stream.firstWhere((state) {
                  return state
                          is RealtimeSuccess<
                            customer_reports.CustomerReportsData
                          > &&
                      state.data.dateRange.endDate == asOf;
                })
                as RealtimeSuccess<customer_reports.CustomerReportsData>;
        expect(state.data.customers.single.currentBalanceCents, 16500);
        expect(state.data.totalReceivablesCents, 16500);
        expect(state.data.agingItems.single.totalCents, 16500);

        final rebuilt = await db.customerDao.recalculateBalance(customerId);
        // Rebuild includes the opening balance and all transactions, including
        // the future transaction because it reconstructs the current cache.
        expect(rebuilt, 26499);
        expect(
          (await db.customerDao.getCustomer(
            customerId,
          ))!.balanceCents.toBigInt().toInt(),
          26499,
        );
      },
    );

    test(
      'supplier aging handles opening credit, returns, and adjustments',
      () async {
        final supplierId = await db
            .into(db.suppliers)
            .insert(
              SuppliersCompanion.insert(
                name: 'Supplier aging',
                currencyId: currencyId,
                openingBalanceCents: Value(Decimal.fromInt(-1000)),
                balanceCents: Value(Decimal.fromInt(99)),
                createdAt: Value(asOf.subtract(const Duration(days: 200))),
              ),
            );

        final movements = <PartyAgingMovement>[
          PartyAgingMovement(
            id: 1,
            amountCents: 5000,
            transactionDate: asOf.subtract(const Duration(days: 40)),
          ),
          PartyAgingMovement(
            id: 2,
            amountCents: 2000,
            transactionDate: asOf.subtract(const Duration(days: 5)),
          ),
          PartyAgingMovement(
            id: 3,
            amountCents: -1000,
            transactionDate: asOf.subtract(const Duration(days: 3)),
          ),
          PartyAgingMovement(
            id: 4,
            amountCents: -500,
            transactionDate: asOf.subtract(const Duration(days: 2)),
          ),
        ];
        for (final movement in movements) {
          await db
              .into(db.supplierTransactions)
              .insert(
                SupplierTransactionsCompanion.insert(
                  supplierId: supplierId,
                  transactionType: movement.amountCents >= 0
                      ? 'adjustment'
                      : 'purchase_return',
                  amountCents: Decimal.fromInt(movement.amountCents),
                  currencyId: currencyId,
                  transactionDate: Value(movement.transactionDate),
                ),
              );
        }

        final records = await PartyAgingLedgerService(
          db,
        ).loadSuppliers(asOf: asOf);
        final buckets = records.single.buckets;
        expect(buckets.days60Cents, 2500);
        expect(buckets.days30Cents, 2000);
        expect(buckets.totalCents, 4500);

        final rebuilt = await db.supplierDao.recalculateBalance(supplierId);
        expect(rebuilt, 4500);
        expect(
          (await db.supplierDao.getSupplier(
            supplierId,
          ))!.balanceCents.toBigInt().toInt(),
          4500,
        );
      },
    );
  });
}
