import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/migrations/offline_sync_ledger.dart';

void main() {
  test(
    'adds customer catalogue pages without losing immutable evidence',
    () async {
      final db = AppDatabase.connect(
        DatabaseConnection(NativeDatabase.memory()),
      );
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();

      await db.customStatement(
        'DROP TRIGGER IF EXISTS trg_sync_catalogue_page_no_delete',
      );
      await db.customStatement(
        'DROP TRIGGER IF EXISTS trg_sync_catalogue_page_no_update',
      );
      await db.customStatement('DROP TABLE sync_catalogue_pages');
      await db.customStatement('''
CREATE TABLE sync_catalogue_pages(
 event_id TEXT PRIMARY KEY CHECK(length(event_id)=36),
 snapshot_id TEXT NOT NULL CHECK(length(snapshot_id)=36),
 entity_type TEXT NOT NULL CHECK(entity_type IN('supplier','category','color','size','product','variant')),
 page_index INTEGER NOT NULL CHECK(page_index>=0),
 page_count INTEGER NOT NULL CHECK(page_count>0 AND page_index<page_count),
 source_database_id TEXT NOT NULL CHECK(length(source_database_id)=36),
 applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE(snapshot_id,entity_type,page_index),
 FOREIGN KEY(event_id) REFERENCES sync_inbox_receipts(event_id) ON DELETE RESTRICT)
''');

      const source = '11111111-1111-4111-8111-111111111111';
      const branch = '22222222-2222-4222-8222-222222222222';
      const eventId = '33333333-3333-4333-8333-333333333333';
      const snapshotId = '44444444-4444-4444-8444-444444444444';
      final organization = await db
          .customSelect(
            'SELECT organization_id FROM business_contexts WHERE id=1',
          )
          .map((row) => row.read<String>('organization_id'))
          .getSingle();
      await db.customStatement(
        '''INSERT INTO sync_source_checkpoints(
      source_database_id,organization_id,branch_id,next_sequence,status)
      VALUES(?,?,?,2,'active')''',
        [source, organization, branch],
      );
      await db.customStatement(
        '''INSERT INTO sync_inbox_receipts(
      event_id,source_database_id,organization_id,branch_id,source_sequence,
      event_type,aggregate_type,aggregate_id,contract_version,event_hash,state,applied_at)
      VALUES(?,?,?,?,1,'catalogue.snapshot_page.v1','catalogue_snapshot',?,1,?,'applied',CURRENT_TIMESTAMP)''',
        [eventId, source, organization, branch, snapshotId, 'a' * 64],
      );
      await db.customStatement(
        '''INSERT INTO sync_catalogue_pages(
      event_id,snapshot_id,entity_type,page_index,page_count,source_database_id)
      VALUES(?,?,'supplier',0,1,?)''',
        [eventId, snapshotId, source],
      );

      await installOfflineSyncLedger(db);

      final definition = await db
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE type='table' "
            "AND name='sync_catalogue_pages'",
          )
          .map((row) => row.read<String>('sql'))
          .getSingle();
      expect(definition, contains("'customer'"));
      final evidence = await db
          .customSelect(
            'SELECT event_id,snapshot_id,entity_type,source_database_id '
            'FROM sync_catalogue_pages',
          )
          .getSingle();
      expect(evidence.read<String>('event_id'), eventId);
      expect(evidence.read<String>('snapshot_id'), snapshotId);
      expect(evidence.read<String>('entity_type'), 'supplier');
      expect(evidence.read<String>('source_database_id'), source);
    },
  );
}
