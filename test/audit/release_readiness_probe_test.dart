// Release regression tests: invalid requests fail without persistent effects.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/settings_dao.dart';
import 'package:tapix/core/services/audit_log_service.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/core/services/lan/lan_network_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:tapix/features/accounting/domain/exceptions/accounting_exception.dart';
import 'package:tapix/features/accounting/domain/models/journal_entry_data.dart';
import 'package:tapix/features/auth/data/services/session_service.dart';
import 'package:tapix/features/purchases/data/datasources/purchase_local_datasource.dart';
import 'package:tapix/features/purchases/data/repositories/purchase_repository_impl.dart';

class _Session extends Mock implements SessionService {}

void main() {
  late AppDatabase db;
  late LanNetworkService master;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    master = LanNetworkService(SettingsDao(db));
    await master.initialize();
  });

  tearDown(() async {
    await master.stop();
    await db.close();
  });

  Future<(int, Map<String, dynamic>)> pair(String code, String device) async {
    final pin = master.snapshot.pairingCode!.split(':').last;
    final client = HttpClient(context: SecurityContext(withTrustedRoots: false))
      ..badCertificateCallback = (cert, host, port) =>
          sha256.convert(cert.der).toString() == pin;
    try {
      final request = await client.postUrl(
        Uri.parse('https://127.0.0.1:${master.snapshot.port}/v1/pair'),
      );
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'pairingCode': code,
          'deviceId': device,
          'deviceName': device,
          'platform': 'test',
        }),
      );
      final response = await request.close();
      final body = jsonDecode(await utf8.decoder.bind(response).join());
      return (response.statusCode, body as Map<String, dynamic>);
    } finally {
      client.close(force: true);
    }
  }

  test(
    'pairing rejects repeated guesses even with the correct code afterwards',
    () async {
      await master.startMaster(port: 0);
      final code = master.snapshot.pairingCode!;
      for (var i = 0; i < 5; i++) {
        // 000000 is outside the generated 100000..999999 code range.
        expect((await pair('000000', 'audit-device')).$1, HttpStatus.forbidden);
      }
      final response = await pair(code, 'audit-device');
      expect(response.$1, HttpStatus.tooManyRequests);
      expect(response.$2.containsKey('token'), isFalse);
      expect(master.snapshot.pairedDevices, 0);
    },
  );

  test(
    'chunked oversized body closes its connection and server remains usable',
    () async {
      await master.startMaster(port: 0);
      final code = master.snapshot.pairingCode!;
      final pin = code.split(':').last;
      final client =
          HttpClient(context: SecurityContext(withTrustedRoots: false))
            ..badCertificateCallback = (cert, host, port) =>
                sha256.convert(cert.der).toString() == pin;
      try {
        final request = await client.postUrl(
          Uri.parse('https://127.0.0.1:${master.snapshot.port}/v1/pair'),
        );
        request.headers.contentType = ContentType.json;
        request.write(List.filled(65537, ' ').join());
        // Cancelling a dart:io request stream also closes its socket. The
        // attacker must not keep streaming; a fresh legitimate client works.
        await expectLater(
          request.close().timeout(const Duration(seconds: 3)),
          throwsA(isA<HttpException>()),
        );
        expect((await pair(code, 'after-oversized')).$1, HttpStatus.ok);
      } finally {
        client.close(force: true);
      }
    },
  );

  test('plaintext HTTP cannot reach the TLS server', () async {
    await master.startMaster(port: 0);
    final client = HttpClient();
    try {
      await expectLater(() async {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:${master.snapshot.port}/v1/health'),
        );
        final response = await request.close().timeout(
          const Duration(seconds: 2),
        );
        await response.drain<void>();
      }(), throwsA(anything));
    } finally {
      client.close(force: true);
    }
  });

  test('wrong master fingerprint is rejected before pairing', () async {
    await master.startMaster(port: 0);
    final clientDb = AppDatabase.connect(
      DatabaseConnection(NativeDatabase.memory()),
    );
    final client = LanNetworkService(SettingsDao(clientDb));
    try {
      await client.initialize();
      final code = master.snapshot.pairingCode!;
      final wrong = '${code.substring(0, 7)}${List.filled(64, '0').join()}';
      final result = await client.pairWithMaster(
        host: '127.0.0.1',
        port: master.snapshot.port,
        pairingCode: wrong,
        deviceName: 'Audit client',
      );
      expect(result.success, isFalse);
      expect(master.snapshot.pairedDevices, 0);
      expect(
        await SettingsDao(clientDb).getSetting('lan.client_token.v2'),
        isNull,
      );
    } finally {
      await client.stop();
      await clientDb.close();
    }
  });

  test('pairing code is single-use under simultaneous requests', () async {
    await master.startMaster(port: 0);
    final code = master.snapshot.pairingCode!;
    final results = await Future.wait([
      pair(code, 'device-a'),
      pair(code, 'device-b'),
    ]);
    expect(results.map((r) => r.$1), unorderedEquals([200, 403]));
    expect(master.snapshot.pairedDevices, 1);
  });

  test('canonical writer rejects negative debit and credit amounts', () async {
    final repo = AccountingRepository(db);
    final cash = await (db.select(
      db.accounts,
    )..where((a) => a.accountCode.equals('1000'))).getSingle();
    final revenue = await (db.select(
      db.accounts,
    )..where((a) => a.accountCode.equals('4000'))).getSingle();
    final entry = JournalEntryData.simple(
      description: 'Audit invalid negative entry',
      debitAccountId: cash.id,
      creditAccountId: revenue.id,
      amountCents: -100,
      currencyId: cash.currencyId,
    );
    expect(entry.isValid, isFalse);
    await expectLater(
      repo.createJournalEntry(entryData: entry, userId: null),
      throwsA(isA<AccountingException>()),
    );
    expect(await db.select(db.journalEntries).get(), isEmpty);
    expect(await db.select(db.journalEntryLines).get(), isEmpty);
  });

  test('corrupt draft cannot post or change account balances', () async {
    final repo = AccountingRepository(db);
    final cash = await (db.select(
      db.accounts,
    )..where((a) => a.accountCode.equals('1000'))).getSingle();
    final revenue = await (db.select(
      db.accounts,
    )..where((a) => a.accountCode.equals('4000'))).getSingle();
    final id = await repo.createJournalEntry(
      entryData: JournalEntryData.simple(
        description: 'Draft corruption regression',
        debitAccountId: cash.id,
        creditAccountId: revenue.id,
        amountCents: 100,
        currencyId: cash.currencyId,
        autoPost: false,
      ),
      userId: null,
    );
    await db.customStatement(
      'UPDATE journal_entry_lines SET debit_cents = -debit_cents, credit_cents = -credit_cents WHERE journal_entry_id = ?',
      [id],
    );
    await db.customStatement(
      'UPDATE journal_entries SET total_debit_cents = -100, total_credit_cents = -100 WHERE id = ?',
      [id],
    );
    await expectLater(
      repo.postJournalEntry(entryId: id, userId: null),
      throwsA(isA<AccountingException>()),
    );
    final header = await (db.select(
      db.journalEntries,
    )..where((e) => e.id.equals(id))).getSingle();
    expect(header.status, 'draft');
    final after = await (db.select(
      db.accounts,
    )..where((a) => a.id.equals(cash.id))).getSingle();
    expect(after.balanceCents, cash.balanceCents);
  });

  test('two simultaneous draft posts update balances only once', () async {
    final repo = AccountingRepository(db);
    final cash = await (db.select(
      db.accounts,
    )..where((a) => a.accountCode.equals('1000'))).getSingle();
    final revenue = await (db.select(
      db.accounts,
    )..where((a) => a.accountCode.equals('4000'))).getSingle();
    final id = await repo.createJournalEntry(
      entryData: JournalEntryData.simple(
        description: 'Concurrent draft posting',
        debitAccountId: cash.id,
        creditAccountId: revenue.id,
        amountCents: 100,
        currencyId: cash.currencyId,
        autoPost: false,
      ),
      userId: null,
    );
    Future<bool> post() async {
      try {
        return await repo.postJournalEntry(entryId: id, userId: null);
      } on AccountingException {
        return false;
      }
    }

    expect(await Future.wait([post(), post()]), unorderedEquals([true, false]));
    final after = await (db.select(
      db.accounts,
    )..where((a) => a.id.equals(cash.id))).getSingle();
    expect(after.balanceCents, cash.balanceCents + Decimal.fromInt(100));
  });

  test(
    'journal failure rolls back purchase and a retry posts exactly once',
    () async {
      final currency = await (db.select(
        db.currencies,
      )..where((c) => c.code.equals('USD'))).getSingle();
      final supplierId = await db
          .into(db.suppliers)
          .insert(
            SuppliersCompanion.insert(
              name: 'Audit supplier',
              currencyId: currency.id,
            ),
          );
      final productId = await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              name: 'Audit product',
              costCents: Decimal.fromInt(100),
              priceCents: Decimal.fromInt(200),
              currencyId: Value(currency.id),
            ),
          );
      final variantId = await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              productId: productId,
              costCents: Decimal.fromInt(100),
              priceCents: Decimal.fromInt(200),
            ),
          );
      final purchaseId = await db
          .into(db.purchases)
          .insert(
            PurchasesCompanion.insert(
              purchaseNumber: 'AUDIT-FAILURE',
              supplierId: supplierId,
              subtotalCents: Decimal.fromInt(100),
              taxCents: Decimal.zero,
              totalCents: Decimal.fromInt(100),
              currencyId: currency.id,
              paymentMethod: const Value('credit'),
            ),
          );
      await db
          .into(db.purchaseItems)
          .insert(
            PurchaseItemsCompanion.insert(
              purchaseId: purchaseId,
              productId: productId,
              variantId: Value(variantId),
              quantity: 1,
              unitCostCents: Decimal.fromInt(100),
              subtotalCents: Decimal.fromInt(100),
              totalCents: Decimal.fromInt(100),
            ),
          );
      final session = _Session();
      when(() => session.getCurrentUserId()).thenAnswer((_) async => null);
      final repo = PurchaseRepositoryImpl(
        PurchaseLocalDatasourceImpl(db.purchaseDao, db.adjustmentReturnDao),
        AuditLogService(db),
        session,
        JournalEntryService(AccountingRepository(db)),
        db,
      );
      // Inject a storage failure at the actual journal persistence boundary.
      await db.customStatement('''CREATE TRIGGER audit_fail_journal
      BEFORE INSERT ON journal_entries BEGIN
      SELECT RAISE(ABORT, 'audit injected journal failure'); END''');
      await expectLater(repo.postPurchase(purchaseId), throwsA(anything));
      expect(
        (await db.purchaseDao.getPurchaseById(purchaseId))!.status,
        'draft',
      );
      final supplier = await (db.select(
        db.suppliers,
      )..where((s) => s.id.equals(supplierId))).getSingle();
      final variant = await (db.select(
        db.productVariants,
      )..where((v) => v.id.equals(variantId))).getSingle();
      expect(supplier.balanceCents, Decimal.zero);
      expect(variant.stockQuantity, 0);
      expect(await db.select(db.journalEntries).get(), isEmpty);
      await db.customStatement('DROP TRIGGER audit_fail_journal');
      await repo.postPurchase(purchaseId);
      final successful = await db.purchaseDao.getPurchaseById(purchaseId);
      expect(successful!.status, 'posted');
      final after = await (db.select(
        db.productVariants,
      )..where((v) => v.id.equals(variantId))).getSingle();
      expect(after.stockQuantity, 1);
      final entries = await db.select(db.journalEntries).get();
      expect(entries, isNotEmpty);
      await expectLater(repo.postPurchase(purchaseId), throwsA(anything));
      expect((await db.select(db.journalEntries).get()).length, entries.length);
      await db.customStatement("""CREATE TRIGGER audit_fail_void
        BEFORE UPDATE OF status ON purchases WHEN NEW.status = 'voided'
        BEGIN SELECT RAISE(ABORT, 'audit injected void failure'); END""");
      await expectLater(repo.voidPurchase(purchaseId), throwsA(anything));
      expect(
        (await db.purchaseDao.getPurchaseById(purchaseId))!.status,
        'posted',
      );
      final afterFailedVoid = await db.select(db.journalEntries).get();
      expect(afterFailedVoid.length, entries.length);
      expect(afterFailedVoid.every((e) => !e.isReversed), isTrue);
      final stockAfterVoid = await (db.select(
        db.productVariants,
      )..where((v) => v.id.equals(variantId))).getSingle();
      expect(stockAfterVoid.stockQuantity, 1);
      await db.customStatement('DROP TRIGGER audit_fail_void');
      await repo.voidPurchase(purchaseId);
      expect(
        (await db.purchaseDao.getPurchaseById(purchaseId))!.status,
        'voided',
      );
    },
  );
}
