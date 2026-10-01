import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/audit_log_service.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/core/services/sync/branch_catalogue_sync_service.dart';
import 'package:tapix/core/services/sync/offline_sync_event_store.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:tapix/features/auth/data/services/session_service.dart';
import 'package:tapix/features/customers/data/datasources/customer_local_datasource.dart';
import 'package:tapix/features/customers/data/repositories/customer_repository_impl.dart';

class _Session extends Fake implements SessionService {
  @override
  Future<int?> getCurrentUserId() async => null;
}

void main() {
  test(
    'branch-created customer publishes identity without financial state',
    () async {
      final db = AppDatabase.connect(
        DatabaseConnection(NativeDatabase.memory()),
      );
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();
      final currencyId = (await (db.select(
        db.currencies,
      )..where((row) => row.code.equals('USD'))).getSingle()).id;
      await OfflineSyncEventStore(db).activateWriterRecording(
        enrollmentId: '11111111-1111-4111-8111-111111111111',
      );
      final repository = CustomerRepositoryImpl(
        CustomerLocalDatasourceImpl(db.customerDao),
        AuditLogService(db),
        _Session(),
        JournalEntryService(AccountingRepository(db)),
        db,
      );

      final customerId = await repository.createCustomer(
        name: 'Branch customer',
        email: 'branch@example.test',
        phone: '01000000000',
        currencyId: currencyId,
        initialBalance: Decimal.zero,
        segment: 'retail',
      );

      final row = await db
          .customSelect(
            'SELECT event_type,aggregate_type,aggregate_id,payload_json '
            'FROM sync_outbox_events',
          )
          .getSingle();
      expect(
        row.read<String>('event_type'),
        BranchCatalogueSyncService.customerProfileEventType,
      );
      expect(row.read<String>('aggregate_type'), 'customer');
      final payload =
          jsonDecode(row.read<String>('payload_json')) as Map<String, dynamic>;
      final customer = payload['customer'] as Map<String, dynamic>;
      expect(payload['contract'], 'customer.profile_upserted');
      expect(customer['globalId'], row.read<String>('aggregate_id'));
      expect(customer['name'], 'Branch customer');
      expect(customer['currencyCode'], 'USD');
      expect(customer, isNot(contains('balanceMinor')));
      expect(customer, isNot(contains('openingBalanceMinor')));
      expect(customer, isNot(contains('loyaltyPointsBalance')));
      expect(customer, isNot(contains('totalSpentMinor')));
      expect(customer, isNot(contains('totalTransactions')));

      final stored = await repository.getCustomer(customerId);
      expect(stored, isNotNull);
      expect(stored!.balanceCents, Decimal.zero);

      expect(await repository.deleteCustomer(customerId), 1);
      final archived = await repository.getCustomer(customerId);
      expect(archived, isNotNull);
      expect(archived!.isActive, isFalse);
      final events = await db
          .customSelect(
            'SELECT payload_json FROM sync_outbox_events '
            "WHERE event_type='customer.profile_upserted.v1' "
            'ORDER BY local_sequence',
          )
          .get();
      expect(events, hasLength(2));
      final archivedPayload =
          jsonDecode(events.last.read<String>('payload_json'))
              as Map<String, dynamic>;
      expect(
        (archivedPayload['customer'] as Map<String, dynamic>)['isActive'],
        isFalse,
      );
    },
  );
}
