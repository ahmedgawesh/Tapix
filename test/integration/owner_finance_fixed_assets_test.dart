import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/fixed_asset_service.dart';
import 'package:tapix/core/services/owner_finance_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';

void main() {
  late AppDatabase db;
  late AccountingRepository accounting;
  late OwnerFinanceService ownerFinance;
  late FixedAssetService fixedAssets;
  late int currencyId;

  Future<Account> account(String code) {
    return (db.select(
      db.accounts,
    )..where((a) => a.accountCode.equals(code))).getSingle();
  }

  Future<Map<String, ({int debit, int credit})>> linesFor(
    String sourceTable,
    int sourceId,
  ) async {
    final rows = await db
        .customSelect(
          'SELECT a.account_code, l.debit_cents, l.credit_cents '
          'FROM journal_entries je '
          'JOIN journal_entry_lines l ON l.journal_entry_id = je.id '
          'JOIN accounts a ON a.id = l.account_id '
          'WHERE je.source_table = ? AND je.source_id = ? AND je.status = ?',
          variables: [
            Variable.withString(sourceTable),
            Variable.withInt(sourceId),
            Variable.withString('posted'),
          ],
        )
        .get();
    return {
      for (final row in rows)
        row.read<String>('account_code'): (
          debit: row.read<int>('debit_cents'),
          credit: row.read<int>('credit_cents'),
        ),
    };
  }

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.customSelect('SELECT 1').get();
    accounting = AccountingRepository(db);
    ownerFinance = OwnerFinanceService(db: db, accounting: accounting);
    fixedAssets = FixedAssetService(db: db, accounting: accounting);
    currencyId = await ownerFinance.getDefaultCurrencyId();
  });

  tearDown(() => db.close());

  group('owner finance', () {
    test(
      'contribution posts Dr Cash / Cr Owner Capital and links document',
      () async {
        final cash = await account('1000');
        final result = await ownerFinance.record(
          type: OwnerFinanceTransactionType.contribution,
          offsetAccountId: cash.id,
          amountCents: 500000,
          currencyId: currencyId,
          transactionDate: DateTime(2026, 1, 5),
          description: 'Initial owner cash contribution',
        );

        final lines = await linesFor(
          'owner_finance_transactions',
          result.transactionId,
        );
        expect(lines['1000'], (debit: 500000, credit: 0));
        expect(lines['3000'], (debit: 0, credit: 500000));

        final document = await (db.select(
          db.ownerFinanceTransactions,
        )..where((t) => t.id.equals(result.transactionId))).getSingle();
        expect(document.status, 'posted');
        expect(document.journalEntryId, result.journalEntryId);
      },
    );

    test(
      'drawings and owner-loan flows use separate control accounts',
      () async {
        final bank = await account('1010');
        final drawing = await ownerFinance.record(
          type: OwnerFinanceTransactionType.withdrawal,
          offsetAccountId: bank.id,
          amountCents: 10000,
          currencyId: currencyId,
          transactionDate: DateTime(2026, 2, 1),
          description: 'Owner drawing',
        );
        final received = await ownerFinance.record(
          type: OwnerFinanceTransactionType.loanReceived,
          offsetAccountId: bank.id,
          amountCents: 30000,
          currencyId: currencyId,
          transactionDate: DateTime(2026, 2, 2),
          description: 'Owner loan received',
        );
        final repaid = await ownerFinance.record(
          type: OwnerFinanceTransactionType.loanRepayment,
          offsetAccountId: bank.id,
          amountCents: 5000,
          currencyId: currencyId,
          transactionDate: DateTime(2026, 2, 3),
          description: 'Owner loan repayment',
        );

        expect(
          (await linesFor(
            'owner_finance_transactions',
            drawing.transactionId,
          ))['3200'],
          (debit: 10000, credit: 0),
        );
        expect(
          (await linesFor(
            'owner_finance_transactions',
            received.transactionId,
          ))['2200'],
          (debit: 0, credit: 30000),
        );
        expect(
          (await linesFor(
            'owner_finance_transactions',
            repaid.transactionId,
          ))['2200'],
          (debit: 5000, credit: 0),
        );
      },
    );

    test('rejects inventory as an offset and voids via reversal', () async {
      final inventory = await account('1200');
      await expectLater(
        ownerFinance.record(
          type: OwnerFinanceTransactionType.contribution,
          offsetAccountId: inventory.id,
          amountCents: 1000,
          currencyId: currencyId,
          transactionDate: DateTime(2026, 1, 1),
          description: 'Unsafe bypass',
        ),
        throwsA(isA<OwnerFinanceException>()),
      );

      final cash = await account('1000');
      final result = await ownerFinance.record(
        type: OwnerFinanceTransactionType.contribution,
        offsetAccountId: cash.id,
        amountCents: 2000,
        currencyId: currencyId,
        transactionDate: DateTime(2026, 1, 2),
        description: 'To be reversed',
      );
      final reversalId = await ownerFinance.voidTransaction(
        transactionId: result.transactionId,
        reason: 'Test correction',
      );
      expect(reversalId, greaterThan(0));

      final document = await (db.select(
        db.ownerFinanceTransactions,
      )..where((t) => t.id.equals(result.transactionId))).getSingle();
      expect(document.status, 'voided');
      expect(document.reversalJournalEntryId, reversalId);
    });
  });

  group('fixed assets', () {
    test('owner-contributed equipment posts Dr 1520 / Cr 3000', () async {
      final equipment = await account('1520');
      final capital = await account('3000');
      final result = await fixedAssets.acquire(
        name: 'Office air conditioner',
        category: 'equipment',
        acquisitionDate: DateTime(2025, 1, 1),
        inServiceDate: DateTime(2025, 1, 1),
        costCents: 120000,
        residualValueCents: 0,
        usefulLifeMonths: 12,
        assetAccountId: equipment.id,
        fundingAccountId: capital.id,
        currencyId: currencyId,
      );

      final lines = await linesFor('fixed_assets', result.assetId);
      expect(lines['1520'], (debit: 120000, credit: 0));
      expect(lines['3000'], (debit: 0, credit: 120000));
    });

    test('straight-line depreciation posts Dr 6100 / Cr 1590', () async {
      final equipment = await account('1520');
      final bank = await account('1010');
      final acquisition = await fixedAssets.acquire(
        name: 'Shop equipment',
        category: 'equipment',
        acquisitionDate: DateTime(2025, 1, 1),
        inServiceDate: DateTime(2025, 1, 1),
        costCents: 120000,
        residualValueCents: 0,
        usefulLifeMonths: 12,
        assetAccountId: equipment.id,
        fundingAccountId: bank.id,
        currencyId: currencyId,
      );

      final depreciation = await fixedAssets.postNextDepreciation(
        assetId: acquisition.assetId,
        asOfDate: DateTime(2025, 1, 31),
      );
      expect(depreciation.amountCents, 10000);
      expect(depreciation.periodEnd, DateTime(2025, 1, 31));

      final lines = await linesFor(
        'fixed_asset_depreciations',
        depreciation.depreciationId,
      );
      expect(lines['6100'], (debit: 10000, credit: 0));
      expect(lines['1590'], (debit: 0, credit: 10000));

      final summary = await fixedAssets.getSummary(
        acquisition.assetId,
        asOfDate: DateTime(2025, 2, 1),
      );
      expect(summary.accumulatedDepreciationCents, 10000);
      expect(summary.carryingAmountCents, 110000);
      expect(summary.postedInstallments, 1);
    });

    test(
      'allocates every cent and never depreciates below residual value',
      () async {
        final furniture = await account('1510');
        final cash = await account('1000');
        final acquisition = await fixedAssets.acquire(
          name: 'Furniture set',
          category: 'furniture',
          acquisitionDate: DateTime(2025, 1, 1),
          inServiceDate: DateTime(2025, 1, 1),
          costCents: 10001,
          residualValueCents: 1001,
          usefulLifeMonths: 3,
          assetAccountId: furniture.id,
          fundingAccountId: cash.id,
          currencyId: currencyId,
        );

        final amounts = <int>[];
        for (final date in [
          DateTime(2025, 1, 31),
          DateTime(2025, 2, 28),
          DateTime(2025, 3, 31),
        ]) {
          amounts.add(
            (await fixedAssets.postNextDepreciation(
              assetId: acquisition.assetId,
              asOfDate: date,
            )).amountCents,
          );
        }

        expect(amounts.fold<int>(0, (a, b) => a + b), 9000);
        final summary = await fixedAssets.getSummary(acquisition.assetId);
        expect(summary.carryingAmountCents, 1001);
        expect(summary.fullyDepreciated, isTrue);
      },
    );

    test(
      'acquisition cannot be voided until latest depreciation is reversed',
      () async {
        final equipment = await account('1520');
        final cash = await account('1000');
        final acquisition = await fixedAssets.acquire(
          name: 'Temporary asset',
          category: 'equipment',
          acquisitionDate: DateTime(2025, 1, 1),
          inServiceDate: DateTime(2025, 1, 1),
          costCents: 12000,
          residualValueCents: 0,
          usefulLifeMonths: 12,
          assetAccountId: equipment.id,
          fundingAccountId: cash.id,
          currencyId: currencyId,
        );
        final depreciation = await fixedAssets.postNextDepreciation(
          assetId: acquisition.assetId,
          asOfDate: DateTime(2025, 1, 31),
        );

        await expectLater(
          fixedAssets.voidAcquisition(
            assetId: acquisition.assetId,
            reason: 'Wrong asset',
          ),
          throwsA(isA<FixedAssetException>()),
        );
        await fixedAssets.voidLatestDepreciation(
          depreciationId: depreciation.depreciationId,
          reason: 'Reverse depreciation first',
        );
        final reversalId = await fixedAssets.voidAcquisition(
          assetId: acquisition.assetId,
          reason: 'Wrong asset',
        );
        expect(reversalId, greaterThan(0));

        final asset = await (db.select(
          db.fixedAssets,
        )..where((a) => a.id.equals(acquisition.assetId))).getSingle();
        expect(asset.status, 'voided');
      },
    );
  });
}
