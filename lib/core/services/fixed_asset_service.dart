import 'dart:math' as math;

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../../features/accounting/data/repositories/accounting_repository.dart';
import '../../features/accounting/domain/models/journal_entry_data.dart';

class FixedAssetException implements Exception {
  final String message;
  const FixedAssetException(this.message);

  @override
  String toString() => 'FixedAssetException: $message';
}

class FixedAssetAcquisitionResult {
  final int assetId;
  final String assetNumber;
  final int journalEntryId;

  const FixedAssetAcquisitionResult({
    required this.assetId,
    required this.assetNumber,
    required this.journalEntryId,
  });
}

class FixedAssetDepreciationResult {
  final int depreciationId;
  final int journalEntryId;
  final int installmentNumber;
  final int amountCents;
  final DateTime periodEnd;

  const FixedAssetDepreciationResult({
    required this.depreciationId,
    required this.journalEntryId,
    required this.installmentNumber,
    required this.amountCents,
    required this.periodEnd,
  });
}

class FixedAssetSummary {
  final FixedAsset asset;
  final int accumulatedDepreciationCents;
  final int carryingAmountCents;
  final int postedInstallments;
  final int? latestDepreciationId;
  final DateTime? nextDepreciationDate;
  final bool depreciationDue;
  final bool fullyDepreciated;

  const FixedAssetSummary({
    required this.asset,
    required this.accumulatedDepreciationCents,
    required this.carryingAmountCents,
    required this.postedInstallments,
    required this.latestDepreciationId,
    required this.nextDepreciationDate,
    required this.depreciationDue,
    required this.fullyDepreciated,
  });
}

/// Fixed-asset acquisition and straight-line depreciation sub-ledger.
///
/// Supported acquisition funding accounts are deliberately explicit:
/// Cash (1000), Bank (1010), Owner Loan (2200), and Owner Capital (3000).
/// Accounts Payable (2000) is excluded because posting directly to it would
/// bypass the supplier sub-ledger.
class FixedAssetService {
  static const allowedAssetAccountCodes = {'1510', '1520'};
  static const allowedFundingAccountCodes = {'1000', '1010', '2200', '3000'};

  final AppDatabase _db;
  final AccountingRepository _accounting;

  FixedAssetService({
    required AppDatabase db,
    required AccountingRepository accounting,
  }) : _db = db,
       _accounting = accounting;

  Stream<List<FixedAsset>> watchAssets() {
    return (_db.select(_db.fixedAssets)..orderBy([
          (a) => OrderingTerm.desc(a.acquisitionDate),
          (a) => OrderingTerm.desc(a.id),
        ]))
        .watch();
  }

  Future<List<Account>> getAssetAccounts() {
    return (_db.select(_db.accounts)
          ..where(
            (a) =>
                a.isActive.equals(true) &
                a.accountCode.isIn(allowedAssetAccountCodes),
          )
          ..orderBy([(a) => OrderingTerm.asc(a.accountCode)]))
        .get();
  }

  Future<List<Account>> getFundingAccounts() {
    return (_db.select(_db.accounts)
          ..where(
            (a) =>
                a.isActive.equals(true) &
                a.accountCode.isIn(allowedFundingAccountCodes),
          )
          ..orderBy([(a) => OrderingTerm.asc(a.accountCode)]))
        .get();
  }

  Future<int> getDefaultCurrencyId() async {
    final currency =
        await (_db.select(_db.currencies)
              ..where((c) => c.isBase.equals(true))
              ..limit(1))
            .getSingleOrNull() ??
        await (_db.select(_db.currencies)..limit(1)).getSingle();
    return currency.id;
  }

  Future<FixedAssetAcquisitionResult> acquire({
    required String name,
    required String category,
    String? description,
    required DateTime acquisitionDate,
    required DateTime inServiceDate,
    required int costCents,
    required int residualValueCents,
    required int usefulLifeMonths,
    required int assetAccountId,
    required int fundingAccountId,
    required int currencyId,
    int? userId,
  }) async {
    final trimmedName = name.trim();
    final trimmedCategory = category.trim();
    if (trimmedName.isEmpty) {
      throw const FixedAssetException('Asset name is required');
    }
    if (trimmedCategory.isEmpty) {
      throw const FixedAssetException('Asset category is required');
    }
    if (costCents <= 0) {
      throw const FixedAssetException('Asset cost must be greater than zero');
    }
    if (residualValueCents < 0 || residualValueCents >= costCents) {
      throw const FixedAssetException(
        'Residual value must be non-negative and lower than cost',
      );
    }
    if (usefulLifeMonths <= 0) {
      throw const FixedAssetException('Useful life must be greater than zero');
    }
    if (_dateOnly(inServiceDate).isBefore(_dateOnly(acquisitionDate))) {
      throw const FixedAssetException(
        'In-service date cannot precede acquisition date',
      );
    }

    return _db.transaction(() async {
      final assetAccount = await _accountById(assetAccountId);
      if (!allowedAssetAccountCodes.contains(assetAccount.accountCode)) {
        throw const FixedAssetException(
          'Use Furniture (1510) or Equipment (1520) as the asset account',
        );
      }
      final fundingAccount = await _accountById(fundingAccountId);
      if (!allowedFundingAccountCodes.contains(fundingAccount.accountCode)) {
        throw const FixedAssetException(
          'Unsupported funding account for fixed-asset acquisition',
        );
      }
      if (assetAccount.currencyId != currencyId ||
          fundingAccount.currencyId != currencyId) {
        throw const FixedAssetException(
          'Asset and funding accounts must use the transaction currency',
        );
      }

      final accumulatedAccount = await _requiredAccountByCode(
        '1590',
        currencyId,
      );
      final expenseAccount = await _requiredAccountByCode('6100', currencyId);
      final assetNumber = await _generateAssetNumber(acquisitionDate);

      final assetId = await _db
          .into(_db.fixedAssets)
          .insert(
            FixedAssetsCompanion.insert(
              assetNumber: assetNumber,
              name: trimmedName,
              category: trimmedCategory,
              description: Value(_trimToNull(description)),
              acquisitionDate: acquisitionDate,
              inServiceDate: inServiceDate,
              costCents: Decimal.fromInt(costCents),
              residualValueCents: Value(Decimal.fromInt(residualValueCents)),
              usefulLifeMonths: usefulLifeMonths,
              assetAccountId: assetAccountId,
              accumulatedDepreciationAccountId: accumulatedAccount.id,
              depreciationExpenseAccountId: expenseAccount.id,
              fundingAccountId: fundingAccountId,
              currencyId: currencyId,
              createdBy: Value(userId),
            ),
          );

      final journalEntryId = await _accounting.createJournalEntry(
        entryData: JournalEntryData.simple(
          description: '$assetNumber — Fixed asset: $trimmedName',
          debitAccountId: assetAccountId,
          creditAccountId: fundingAccountId,
          amountCents: costCents,
          currencyId: currencyId,
          entryDate: acquisitionDate,
          entryType: 'fixed_asset_acquisition',
          sourceTable: 'fixed_assets',
          sourceId: assetId,
          autoPost: true,
        ),
        userId: userId,
      );

      await (_db.update(
        _db.fixedAssets,
      )..where((a) => a.id.equals(assetId))).write(
        FixedAssetsCompanion(
          acquisitionJournalEntryId: Value(journalEntryId),
          updatedAt: Value(DateTime.now()),
        ),
      );

      return FixedAssetAcquisitionResult(
        assetId: assetId,
        assetNumber: assetNumber,
        journalEntryId: journalEntryId,
      );
    });
  }

  Future<FixedAssetSummary> getSummary(
    int assetId, {
    DateTime? asOfDate,
  }) async {
    final asset = await (_db.select(
      _db.fixedAssets,
    )..where((a) => a.id.equals(assetId))).getSingleOrNull();
    if (asset == null) {
      throw const FixedAssetException('Fixed asset not found');
    }
    final posted =
        await (_db.select(_db.fixedAssetDepreciations)
              ..where(
                (d) => d.assetId.equals(assetId) & d.status.equals('posted'),
              )
              ..orderBy([(d) => OrderingTerm.asc(d.periodEnd)]))
            .get();

    final accumulated = posted.fold<int>(
      0,
      (sum, row) => sum + row.amountCents.toBigInt().toInt(),
    );
    final cost = asset.costCents.toBigInt().toInt();
    final residual = asset.residualValueCents.toBigInt().toInt();
    final carrying = math.max(residual, cost - accumulated);
    final complete =
        posted.length >= asset.usefulLifeMonths ||
        accumulated >= cost - residual;
    final nextDate = complete
        ? null
        : _addMonths(
            asset.inServiceDate,
            posted.length + 1,
          ).subtract(const Duration(days: 1));
    final today = _dateOnly(asOfDate ?? DateTime.now());

    return FixedAssetSummary(
      asset: asset,
      accumulatedDepreciationCents: accumulated,
      carryingAmountCents: carrying,
      postedInstallments: posted.length,
      latestDepreciationId: posted.isEmpty ? null : posted.last.id,
      nextDepreciationDate: nextDate,
      depreciationDue:
          asset.status == 'active' &&
          nextDate != null &&
          !_dateOnly(nextDate).isAfter(today),
      fullyDepreciated: complete,
    );
  }

  Future<FixedAssetDepreciationResult> postNextDepreciation({
    required int assetId,
    DateTime? asOfDate,
    String? notes,
    int? userId,
  }) {
    return _db.transaction(() async {
      final asset = await (_db.select(
        _db.fixedAssets,
      )..where((a) => a.id.equals(assetId))).getSingleOrNull();
      if (asset == null || asset.status != 'active') {
        throw const FixedAssetException('Active fixed asset not found');
      }

      final allRows =
          await (_db.select(_db.fixedAssetDepreciations)
                ..where((d) => d.assetId.equals(assetId))
                ..orderBy([(d) => OrderingTerm.asc(d.installmentNumber)]))
              .get();
      final postedRows = allRows
          .where((row) => row.status == 'posted')
          .toList();
      final scheduleIndex = postedRows.length;
      if (scheduleIndex >= asset.usefulLifeMonths) {
        throw const FixedAssetException('Asset is fully depreciated');
      }

      final periodStart = _addMonths(asset.inServiceDate, scheduleIndex);
      final periodEnd = _addMonths(
        asset.inServiceDate,
        scheduleIndex + 1,
      ).subtract(const Duration(days: 1));
      final allowedDate = _dateOnly(asOfDate ?? DateTime.now());
      if (_dateOnly(periodEnd).isAfter(allowedDate)) {
        throw FixedAssetException(
          'Next depreciation is not due until ${periodEnd.toIso8601String().substring(0, 10)}',
        );
      }

      final cost = asset.costCents.toBigInt().toInt();
      final residual = asset.residualValueCents.toBigInt().toInt();
      final depreciable = cost - residual;
      final base = depreciable ~/ asset.usefulLifeMonths;
      final remainder = depreciable % asset.usefulLifeMonths;
      final amount = base + (scheduleIndex < remainder ? 1 : 0);
      if (amount <= 0) {
        throw const FixedAssetException('Calculated depreciation is zero');
      }

      final nextSequence = allRows.isEmpty
          ? 1
          : allRows.map((row) => row.installmentNumber).reduce(math.max) + 1;

      final depreciationId = await _db
          .into(_db.fixedAssetDepreciations)
          .insert(
            FixedAssetDepreciationsCompanion.insert(
              assetId: assetId,
              installmentNumber: nextSequence,
              periodStart: periodStart,
              periodEnd: periodEnd,
              amountCents: Decimal.fromInt(amount),
              notes: Value(_trimToNull(notes)),
              postedBy: Value(userId),
            ),
          );

      final journalEntryId = await _accounting.createJournalEntry(
        entryData: JournalEntryData.simple(
          description:
              '${asset.assetNumber} — Depreciation ${scheduleIndex + 1}/${asset.usefulLifeMonths}',
          debitAccountId: asset.depreciationExpenseAccountId,
          creditAccountId: asset.accumulatedDepreciationAccountId,
          amountCents: amount,
          currencyId: asset.currencyId,
          entryDate: periodEnd,
          entryType: 'fixed_asset_depreciation',
          sourceTable: 'fixed_asset_depreciations',
          sourceId: depreciationId,
          autoPost: true,
        ),
        userId: userId,
      );

      await (_db.update(
        _db.fixedAssetDepreciations,
      )..where((d) => d.id.equals(depreciationId))).write(
        FixedAssetDepreciationsCompanion(journalEntryId: Value(journalEntryId)),
      );
      await (_db.update(_db.fixedAssets)..where((a) => a.id.equals(assetId)))
          .write(FixedAssetsCompanion(updatedAt: Value(DateTime.now())));

      return FixedAssetDepreciationResult(
        depreciationId: depreciationId,
        journalEntryId: journalEntryId,
        installmentNumber: nextSequence,
        amountCents: amount,
        periodEnd: periodEnd,
      );
    });
  }

  Future<int> voidLatestDepreciation({
    required int depreciationId,
    required String reason,
    int? userId,
  }) {
    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw const FixedAssetException('Void reason is required');
    }

    return _db.transaction(() async {
      final row = await (_db.select(
        _db.fixedAssetDepreciations,
      )..where((d) => d.id.equals(depreciationId))).getSingleOrNull();
      if (row == null || row.status != 'posted' || row.journalEntryId == null) {
        throw const FixedAssetException(
          'Posted depreciation instalment not found',
        );
      }
      final latest =
          await (_db.select(_db.fixedAssetDepreciations)
                ..where(
                  (d) =>
                      d.assetId.equals(row.assetId) & d.status.equals('posted'),
                )
                ..orderBy([
                  (d) => OrderingTerm.desc(d.periodEnd),
                  (d) => OrderingTerm.desc(d.id),
                ])
                ..limit(1))
              .getSingle();
      if (latest.id != row.id) {
        throw const FixedAssetException(
          'Only the latest depreciation instalment can be voided',
        );
      }

      final reversalId = await _accounting.voidJournalEntry(
        entryId: row.journalEntryId!,
        reason: trimmedReason,
        userId: userId,
      );
      await (_db.update(
        _db.fixedAssetDepreciations,
      )..where((d) => d.id.equals(row.id))).write(
        FixedAssetDepreciationsCompanion(
          status: const Value('voided'),
          reversalJournalEntryId: Value(reversalId),
        ),
      );
      await (_db.update(_db.fixedAssets)
            ..where((a) => a.id.equals(row.assetId)))
          .write(FixedAssetsCompanion(updatedAt: Value(DateTime.now())));
      return reversalId;
    });
  }

  Future<int> voidAcquisition({
    required int assetId,
    required String reason,
    int? userId,
  }) {
    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw const FixedAssetException('Void reason is required');
    }

    return _db.transaction(() async {
      final asset = await (_db.select(
        _db.fixedAssets,
      )..where((a) => a.id.equals(assetId))).getSingleOrNull();
      if (asset == null ||
          asset.status != 'active' ||
          asset.acquisitionJournalEntryId == null) {
        throw const FixedAssetException('Active fixed asset not found');
      }
      final depreciationCount =
          await (_db.selectOnly(_db.fixedAssetDepreciations)
                ..addColumns([_db.fixedAssetDepreciations.id.count()])
                ..where(
                  _db.fixedAssetDepreciations.assetId.equals(assetId) &
                      _db.fixedAssetDepreciations.status.equals('posted'),
                ))
              .map(
                (row) => row.read(_db.fixedAssetDepreciations.id.count()) ?? 0,
              )
              .getSingle();
      if (depreciationCount > 0) {
        throw const FixedAssetException(
          'Void posted depreciation before voiding the asset acquisition',
        );
      }

      final reversalId = await _accounting.voidJournalEntry(
        entryId: asset.acquisitionJournalEntryId!,
        reason: trimmedReason,
        userId: userId,
      );
      await (_db.update(
        _db.fixedAssets,
      )..where((a) => a.id.equals(assetId))).write(
        FixedAssetsCompanion(
          status: const Value('voided'),
          reversalJournalEntryId: Value(reversalId),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return reversalId;
    });
  }

  Future<Account> _accountById(int id) async {
    final account = await (_db.select(
      _db.accounts,
    )..where((a) => a.id.equals(id))).getSingleOrNull();
    if (account == null || !account.isActive) {
      throw const FixedAssetException('Selected account is unavailable');
    }
    return account;
  }

  Future<Account> _requiredAccountByCode(String code, int currencyId) async {
    final account = await _accounting.getAccountByCode(code);
    if (account == null || !account.isActive) {
      throw FixedAssetException('Required account $code is unavailable');
    }
    if (account.currencyId != currencyId) {
      throw FixedAssetException(
        'Required account $code uses a different currency',
      );
    }
    return account;
  }

  Future<String> _generateAssetNumber(DateTime date) async {
    final prefix = 'FA-${date.year}${date.month.toString().padLeft(2, '0')}';
    final last =
        await (_db.select(_db.fixedAssets)
              ..where((a) => a.assetNumber.like('$prefix-%'))
              ..orderBy([(a) => OrderingTerm.desc(a.assetNumber)])
              ..limit(1))
            .getSingleOrNull();
    final lastSequence =
        int.tryParse(last?.assetNumber.split('-').last ?? '') ?? 0;
    return '$prefix-${(lastSequence + 1).toString().padLeft(4, '0')}';
  }

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static DateTime _addMonths(DateTime date, int months) {
    final zeroBased = date.year * 12 + date.month - 1 + months;
    final year = zeroBased ~/ 12;
    final month = zeroBased % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(
      year,
      month,
      math.min(date.day, lastDay),
      date.hour,
      date.minute,
      date.second,
      date.millisecond,
      date.microsecond,
    );
  }

  static String? _trimToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
