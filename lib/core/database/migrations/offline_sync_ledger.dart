import '../app_database.dart';

/// Additive append-only ledgers for offline branch synchronization.
/// Installed on every open so released databases receive the sidecar without
/// rewriting accounting, stock, or historical documents.
Future<void> installOfflineSyncLedger(AppDatabase db) async {
  await db.customStatement('''
CREATE TABLE IF NOT EXISTS sync_local_state(
 id INTEGER PRIMARY KEY CHECK(id=1), database_id TEXT NOT NULL UNIQUE CHECK(length(database_id)=36),
 organization_id TEXT NOT NULL CHECK(length(organization_id)=36), branch_id TEXT NOT NULL CHECK(length(branch_id)=36),
 next_sequence INTEGER NOT NULL DEFAULT 1 CHECK(next_sequence>0), created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)
''');
  await db.customStatement('''
INSERT INTO sync_local_state(id,database_id,organization_id,branch_id,next_sequence)
SELECT 1,database_id,organization_id,branch_id,1 FROM business_contexts WHERE id=1
ON CONFLICT(id) DO NOTHING
''');
  await db.customStatement(
    '''CREATE TRIGGER IF NOT EXISTS trg_sync_local_no_delete BEFORE DELETE ON sync_local_state
BEGIN SELECT RAISE(ABORT,'Sync local identity cannot be deleted'); END''',
  );
  await db.customStatement(
    '''CREATE TRIGGER IF NOT EXISTS trg_sync_local_update BEFORE UPDATE ON sync_local_state
WHEN NEW.id IS NOT OLD.id OR NEW.database_id IS NOT OLD.database_id
 OR NEW.organization_id IS NOT OLD.organization_id OR NEW.branch_id IS NOT OLD.branch_id
 OR NEW.created_at IS NOT OLD.created_at OR NEW.next_sequence<>OLD.next_sequence+1
BEGIN SELECT RAISE(ABORT,'Invalid sync sequence update'); END''',
  );

  // Recording is opt-in. A normal single-branch or LAN-only Pro installation
  // does not accumulate a cloud outbox until the online branch provisioning
  // flow records a central enrollment.
  await db.customStatement('''
CREATE TABLE IF NOT EXISTS sync_writer_enrollment(
 id INTEGER PRIMARY KEY CHECK(id=1),
 enrollment_id TEXT NOT NULL UNIQUE CHECK(length(enrollment_id)=36),
 database_id TEXT NOT NULL CHECK(length(database_id)=36),
 organization_id TEXT NOT NULL CHECK(length(organization_id)=36),
 branch_id TEXT NOT NULL CHECK(length(branch_id)=36),
 enrolled_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)
''');
  await db.customStatement(
    '''CREATE TRIGGER IF NOT EXISTS trg_sync_writer_enrollment_identity BEFORE INSERT ON sync_writer_enrollment
WHEN NOT EXISTS(SELECT 1 FROM sync_local_state s WHERE s.id=1
 AND s.database_id=NEW.database_id AND s.organization_id=NEW.organization_id
 AND s.branch_id=NEW.branch_id)
BEGIN SELECT RAISE(ABORT,'Sync writer enrollment identity mismatch'); END''',
  );
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS trg_sync_writer_enrollment_no_update BEFORE UPDATE ON sync_writer_enrollment BEGIN SELECT RAISE(ABORT,'Sync writer enrollment is immutable'); END",
  );
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS trg_sync_writer_enrollment_no_delete BEFORE DELETE ON sync_writer_enrollment BEGIN SELECT RAISE(ABORT,'Sync writer enrollment cannot be deleted'); END",
  );

  await db.customStatement('''
CREATE TABLE IF NOT EXISTS sync_outbox_events(
 event_id TEXT PRIMARY KEY CHECK(length(event_id)=36), source_database_id TEXT NOT NULL CHECK(length(source_database_id)=36),
 organization_id TEXT NOT NULL CHECK(length(organization_id)=36), branch_id TEXT NOT NULL CHECK(length(branch_id)=36),
 local_sequence INTEGER NOT NULL CHECK(local_sequence>0), event_type TEXT NOT NULL CHECK(length(trim(event_type))>0),
 aggregate_type TEXT NOT NULL CHECK(length(trim(aggregate_type))>0), aggregate_id TEXT NOT NULL CHECK(length(trim(aggregate_id))>0),
 contract_version INTEGER NOT NULL CHECK(contract_version>0), payload_json TEXT NOT NULL CHECK(json_valid(payload_json)),
 event_hash TEXT NOT NULL CHECK(length(event_hash)=64), occurred_at TEXT NOT NULL,
 state TEXT NOT NULL DEFAULT 'pending' CHECK(state IN('pending','leased','delivered','dead_letter')),
 attempt_count INTEGER NOT NULL DEFAULT 0 CHECK(attempt_count>=0), next_attempt_at TEXT NOT NULL,
 lease_token TEXT, lease_until TEXT, delivered_at TEXT, last_error TEXT, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE(source_database_id,local_sequence),
 CHECK((state='pending' AND lease_token IS NULL AND lease_until IS NULL AND delivered_at IS NULL)
 OR(state='leased' AND lease_token IS NOT NULL AND lease_until IS NOT NULL AND delivered_at IS NULL)
 OR(state='delivered' AND lease_token IS NULL AND lease_until IS NULL AND delivered_at IS NOT NULL)
 OR(state='dead_letter' AND lease_token IS NULL AND lease_until IS NULL AND delivered_at IS NULL AND last_error IS NOT NULL)))
''');
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_sync_outbox_dispatch ON sync_outbox_events(state,local_sequence,next_attempt_at)',
  );
  await db.customStatement(
    '''CREATE TRIGGER IF NOT EXISTS trg_sync_outbox_insert BEFORE INSERT ON sync_outbox_events
WHEN NOT EXISTS(SELECT 1 FROM sync_local_state s WHERE s.id=1 AND s.database_id=NEW.source_database_id
 AND s.organization_id=NEW.organization_id AND s.branch_id=NEW.branch_id AND NEW.local_sequence=s.next_sequence-1)
BEGIN SELECT RAISE(ABORT,'Invalid local sync event identity or sequence'); END''',
  );
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS trg_sync_outbox_no_delete BEFORE DELETE ON sync_outbox_events BEGIN SELECT RAISE(ABORT,'Sync outbox is append-only'); END",
  );
  await db.customStatement(
    '''CREATE TRIGGER IF NOT EXISTS trg_sync_outbox_immutable BEFORE UPDATE OF
 event_id,source_database_id,organization_id,branch_id,local_sequence,event_type,aggregate_type,aggregate_id,
 contract_version,payload_json,event_hash,occurred_at,created_at ON sync_outbox_events
BEGIN SELECT RAISE(ABORT,'Sync event payload is immutable'); END''',
  );
  await db.customStatement(
    '''CREATE TRIGGER IF NOT EXISTS trg_sync_outbox_state BEFORE UPDATE ON sync_outbox_events
WHEN NOT((OLD.state IN('pending','leased') AND NEW.state='leased' AND NEW.attempt_count=OLD.attempt_count+1)
 OR(OLD.state='leased' AND NEW.state='delivered' AND NEW.attempt_count=OLD.attempt_count)
 OR(OLD.state='leased' AND NEW.state IN('pending','dead_letter') AND NEW.attempt_count=OLD.attempt_count))
BEGIN SELECT RAISE(ABORT,'Invalid sync outbox state transition'); END''',
  );

  await db.customStatement('''
CREATE TABLE IF NOT EXISTS sync_source_checkpoints(
 source_database_id TEXT PRIMARY KEY CHECK(length(source_database_id)=36),
 organization_id TEXT NOT NULL CHECK(length(organization_id)=36), branch_id TEXT NOT NULL CHECK(length(branch_id)=36),
 next_sequence INTEGER NOT NULL CHECK(next_sequence>0), status TEXT NOT NULL DEFAULT 'active' CHECK(status IN('active','quarantined')),
 enrolled_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)
''');
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS trg_sync_checkpoint_no_delete BEFORE DELETE ON sync_source_checkpoints BEGIN SELECT RAISE(ABORT,'Sync source enrollment cannot be deleted'); END",
  );
  await db.customStatement(
    '''CREATE TRIGGER IF NOT EXISTS trg_sync_checkpoint_update BEFORE UPDATE ON sync_source_checkpoints
WHEN NEW.source_database_id IS NOT OLD.source_database_id OR NEW.organization_id IS NOT OLD.organization_id
 OR NEW.branch_id IS NOT OLD.branch_id OR NEW.enrolled_at IS NOT OLD.enrolled_at
 OR NEW.next_sequence NOT IN(OLD.next_sequence,OLD.next_sequence+1)
BEGIN SELECT RAISE(ABORT,'Invalid sync checkpoint update'); END''',
  );

  await db.customStatement('''
CREATE TABLE IF NOT EXISTS sync_inbox_receipts(
 event_id TEXT PRIMARY KEY CHECK(length(event_id)=36), source_database_id TEXT NOT NULL CHECK(length(source_database_id)=36),
 organization_id TEXT NOT NULL CHECK(length(organization_id)=36), branch_id TEXT NOT NULL CHECK(length(branch_id)=36),
 source_sequence INTEGER NOT NULL CHECK(source_sequence>0), event_type TEXT NOT NULL, aggregate_type TEXT NOT NULL, aggregate_id TEXT NOT NULL,
 contract_version INTEGER NOT NULL CHECK(contract_version>0), event_hash TEXT NOT NULL CHECK(length(event_hash)=64),
 state TEXT NOT NULL CHECK(state IN('applying','applied')), received_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, applied_at TEXT,
 UNIQUE(source_database_id,source_sequence),
 CHECK((state='applying' AND applied_at IS NULL) OR(state='applied' AND applied_at IS NOT NULL)),
 FOREIGN KEY(source_database_id) REFERENCES sync_source_checkpoints(source_database_id) ON DELETE RESTRICT)
''');
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS trg_sync_inbox_no_delete BEFORE DELETE ON sync_inbox_receipts BEGIN SELECT RAISE(ABORT,'Sync inbox is append-only'); END",
  );
  await db.customStatement(
    '''CREATE TRIGGER IF NOT EXISTS trg_sync_inbox_complete BEFORE UPDATE ON sync_inbox_receipts
WHEN OLD.state<>'applying' OR NEW.state<>'applied' OR NEW.event_id IS NOT OLD.event_id
 OR NEW.source_database_id IS NOT OLD.source_database_id OR NEW.organization_id IS NOT OLD.organization_id
 OR NEW.branch_id IS NOT OLD.branch_id OR NEW.source_sequence IS NOT OLD.source_sequence
 OR NEW.event_type IS NOT OLD.event_type OR NEW.aggregate_type IS NOT OLD.aggregate_type
 OR NEW.aggregate_id IS NOT OLD.aggregate_id OR NEW.contract_version IS NOT OLD.contract_version
 OR NEW.event_hash IS NOT OLD.event_hash OR NEW.received_at IS NOT OLD.received_at OR NEW.applied_at IS NULL
BEGIN SELECT RAISE(ABORT,'Sync inbox receipt can only be completed once'); END''',
  );
  await db.customStatement('''
CREATE TABLE IF NOT EXISTS sync_entity_identities(
 entity_type TEXT NOT NULL CHECK(entity_type IN('product','product_variant','supplier','customer')),
 local_id INTEGER NOT NULL CHECK(local_id>0), global_id TEXT NOT NULL CHECK(length(global_id)=36),
 origin_database_id TEXT NOT NULL CHECK(length(origin_database_id)=36),
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 PRIMARY KEY(entity_type,local_id), UNIQUE(entity_type,global_id))
''');
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS trg_sync_entity_identity_no_delete BEFORE DELETE ON sync_entity_identities BEGIN SELECT RAISE(ABORT,'Sync entity identity cannot be deleted'); END",
  );
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS trg_sync_entity_identity_no_update BEFORE UPDATE ON sync_entity_identities BEGIN SELECT RAISE(ABORT,'Sync entity identity is immutable'); END",
  );
  await db.customStatement(
    '''CREATE TRIGGER IF NOT EXISTS trg_sync_entity_identity_target BEFORE INSERT ON sync_entity_identities
WHEN (NEW.entity_type='product' AND NOT EXISTS(SELECT 1 FROM products WHERE id=NEW.local_id))
 OR (NEW.entity_type='product_variant' AND NOT EXISTS(SELECT 1 FROM product_variants WHERE id=NEW.local_id))
 OR (NEW.entity_type='supplier' AND NOT EXISTS(SELECT 1 FROM suppliers WHERE id=NEW.local_id))
 OR (NEW.entity_type='customer' AND NOT EXISTS(SELECT 1 FROM customers WHERE id=NEW.local_id))
BEGIN SELECT RAISE(ABORT,'Sync entity target does not exist'); END''',
  );

  // Inventory layers have a different lifecycle from master data. Keep their
  // identity in a dedicated append-only sidecar so older installations of the
  // generic identity table can be extended without rebuilding it.
  await db.customStatement('''
CREATE TABLE IF NOT EXISTS sync_inventory_layer_identities(
 local_batch_id INTEGER PRIMARY KEY CHECK(local_batch_id>0),
 global_id TEXT NOT NULL UNIQUE CHECK(length(global_id)=36),
 origin_database_id TEXT NOT NULL CHECK(length(origin_database_id)=36),
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)
''');
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS trg_sync_inventory_layer_identity_no_delete BEFORE DELETE ON sync_inventory_layer_identities BEGIN SELECT RAISE(ABORT,'Sync inventory layer identity cannot be deleted'); END",
  );
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS trg_sync_inventory_layer_identity_no_update BEFORE UPDATE ON sync_inventory_layer_identities BEGIN SELECT RAISE(ABORT,'Sync inventory layer identity is immutable'); END",
  );
  await db.customStatement(
    '''CREATE TRIGGER IF NOT EXISTS trg_sync_inventory_layer_identity_target BEFORE INSERT ON sync_inventory_layer_identities
WHEN NOT EXISTS(SELECT 1 FROM product_batches WHERE id=NEW.local_batch_id)
BEGIN SELECT RAISE(ABORT,'Sync inventory layer target does not exist'); END''',
  );
}
