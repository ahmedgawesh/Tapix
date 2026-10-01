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

  // Delivery is tracked per remote database. A single global outbox state is
  // insufficient once the coordinator serves more than one independent
  // branch: acknowledging an event for branch A must never hide it from B.
  await db.customStatement('''
CREATE TABLE IF NOT EXISTS sync_delivery_peers(
 target_database_id TEXT PRIMARY KEY CHECK(length(target_database_id)=36),
 organization_id TEXT NOT NULL CHECK(length(organization_id)=36),
 branch_id TEXT NOT NULL CHECK(length(branch_id)=36),
 status TEXT NOT NULL DEFAULT 'active' CHECK(status IN('active','quarantined','revoked')),
 first_sequence INTEGER NOT NULL DEFAULT 1 CHECK(first_sequence>0),
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)
''');
  // Cloud accepts only the authenticated writer's own stream. It must not
  // receive relay copies that already arrived from LAN or the cloud itself.
  final peerColumns = await db
      .customSelect('PRAGMA table_info(sync_delivery_peers)')
      .get();
  if (!peerColumns.any(
    (row) => row.read<String>('name') == 'relay_remote_events',
  )) {
    await db.customStatement(
      'ALTER TABLE sync_delivery_peers ADD COLUMN relay_remote_events INTEGER NOT NULL DEFAULT 1 CHECK(relay_remote_events IN (0,1))',
    );
  }
  await db.customStatement(
    '''CREATE TRIGGER IF NOT EXISTS trg_sync_peer_relay_policy
BEFORE UPDATE OF relay_remote_events ON sync_delivery_peers
WHEN NEW.relay_remote_events IS NOT OLD.relay_remote_events
BEGIN SELECT RAISE(ABORT,'Sync peer relay policy is immutable'); END''',
  );
  await db.customStatement('''
CREATE TABLE IF NOT EXISTS sync_outbox_deliveries(
 target_database_id TEXT NOT NULL,
 event_id TEXT NOT NULL,
 source_sequence INTEGER NOT NULL CHECK(source_sequence>0),
 state TEXT NOT NULL DEFAULT 'pending' CHECK(state IN('pending','leased','delivered','dead_letter')),
 attempt_count INTEGER NOT NULL DEFAULT 0 CHECK(attempt_count>=0),
 next_attempt_at TEXT NOT NULL,
 lease_token TEXT,
 lease_until TEXT,
 delivered_at TEXT,
 last_error TEXT,
 PRIMARY KEY(target_database_id,event_id),
 UNIQUE(target_database_id,source_sequence),
 FOREIGN KEY(target_database_id) REFERENCES sync_delivery_peers(target_database_id) ON DELETE RESTRICT,
 FOREIGN KEY(event_id) REFERENCES sync_outbox_events(event_id) ON DELETE RESTRICT)
''');
  await db.customStatement('''
CREATE INDEX IF NOT EXISTS idx_sync_outbox_deliveries_dispatch
ON sync_outbox_deliveries(target_database_id,source_sequence,state,next_attempt_at)
''');
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS trg_sync_delivery_peer_no_delete BEFORE DELETE ON sync_delivery_peers BEGIN SELECT RAISE(ABORT,'LAN sync peer evidence cannot be deleted'); END",
  );
  await db.customStatement('''
CREATE TRIGGER IF NOT EXISTS trg_sync_delivery_peer_identity
BEFORE UPDATE ON sync_delivery_peers
WHEN NEW.target_database_id IS NOT OLD.target_database_id
 OR NEW.organization_id IS NOT OLD.organization_id
 OR NEW.branch_id IS NOT OLD.branch_id
 OR NEW.first_sequence IS NOT OLD.first_sequence
 OR NEW.created_at IS NOT OLD.created_at
BEGIN SELECT RAISE(ABORT,'LAN sync peer identity is immutable'); END
''');
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS trg_sync_outbox_delivery_no_delete BEFORE DELETE ON sync_outbox_deliveries BEGIN SELECT RAISE(ABORT,'LAN sync delivery evidence cannot be deleted'); END",
  );
  await db.customStatement('''
CREATE TRIGGER IF NOT EXISTS trg_sync_outbox_delivery_identity
BEFORE UPDATE ON sync_outbox_deliveries
WHEN NEW.target_database_id IS NOT OLD.target_database_id
 OR NEW.event_id IS NOT OLD.event_id
 OR NEW.source_sequence IS NOT OLD.source_sequence
BEGIN SELECT RAISE(ABORT,'LAN sync delivery identity is immutable'); END
''');
  await db.customStatement('''
CREATE TRIGGER IF NOT EXISTS trg_sync_outbox_delivery_state
BEFORE UPDATE ON sync_outbox_deliveries
WHEN NOT(
 (OLD.state IN('pending','leased') AND NEW.state='leased'
   AND NEW.attempt_count=OLD.attempt_count+1
   AND NEW.lease_token IS NOT NULL AND NEW.lease_until IS NOT NULL
   AND NEW.delivered_at IS NULL)
 OR(OLD.state='leased' AND NEW.state='delivered'
   AND NEW.attempt_count=OLD.attempt_count
   AND NEW.lease_token IS NULL AND NEW.lease_until IS NULL
   AND NEW.delivered_at IS NOT NULL)
 OR(OLD.state='leased' AND NEW.state IN('pending','dead_letter')
   AND NEW.attempt_count=OLD.attempt_count
   AND NEW.lease_token IS NULL AND NEW.lease_until IS NULL
   AND NEW.delivered_at IS NULL
   AND (NEW.state<>'dead_letter' OR NEW.last_error IS NOT NULL))
)
BEGIN SELECT RAISE(ABORT,'Invalid LAN sync delivery transition'); END
''');
  await db.customStatement(
    '''CREATE TRIGGER IF NOT EXISTS trg_sync_local_update BEFORE UPDATE ON sync_local_state
WHEN NEW.id IS NOT OLD.id OR NEW.database_id IS NOT OLD.database_id
 OR NEW.organization_id IS NOT OLD.organization_id OR NEW.branch_id IS NOT OLD.branch_id
 OR NEW.created_at IS NOT OLD.created_at OR NEW.next_sequence<>OLD.next_sequence+1
BEGIN SELECT RAISE(ABORT,'Invalid sync sequence update'); END''',
  );

  // Recording is opt-in. A normal single-branch installation does not build an
  // outbox. Independent LAN branches are enrolled by the local Pro coordinator;
  // internet branches are enrolled by the separately entitled coordinator.
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
  // Immutable payload projection used by company reports, diagnostics, and
  // deterministic rebuilds. Operational projectors consume the same envelope;
  // storing it here does not post a second journal entry in the receiver.
  await db.customStatement('''
CREATE TABLE IF NOT EXISTS sync_remote_event_projections(
 event_id TEXT PRIMARY KEY CHECK(length(event_id)=36),
 source_database_id TEXT NOT NULL CHECK(length(source_database_id)=36),
 organization_id TEXT NOT NULL CHECK(length(organization_id)=36),
 branch_id TEXT NOT NULL CHECK(length(branch_id)=36),
 source_sequence INTEGER NOT NULL CHECK(source_sequence>0),
 event_type TEXT NOT NULL,
 aggregate_type TEXT NOT NULL,
 aggregate_id TEXT NOT NULL,
 contract_version INTEGER NOT NULL CHECK(contract_version>0),
 payload_json TEXT NOT NULL CHECK(json_valid(payload_json)),
 event_hash TEXT NOT NULL CHECK(length(event_hash)=64),
 occurred_at TEXT NOT NULL,
 projected_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE(source_database_id,source_sequence),
 FOREIGN KEY(event_id) REFERENCES sync_inbox_receipts(event_id) ON DELETE RESTRICT)
''');
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS trg_sync_remote_projection_no_update BEFORE UPDATE ON sync_remote_event_projections BEGIN SELECT RAISE(ABORT,'Remote sync projection is immutable'); END",
  );
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS trg_sync_remote_projection_no_delete BEFORE DELETE ON sync_remote_event_projections BEGIN SELECT RAISE(ABORT,'Remote sync projection cannot be deleted'); END",
  );
  // Coordinator relay state. Remote events keep their original source and
  // sequence; the coordinator never republishes them as locally-authored
  // events. Each destination acknowledges its own immutable delivery row.
  await db.customStatement('''
CREATE TABLE IF NOT EXISTS sync_relay_deliveries(
 target_database_id TEXT NOT NULL,
 event_id TEXT NOT NULL,
 source_database_id TEXT NOT NULL CHECK(length(source_database_id)=36),
 source_sequence INTEGER NOT NULL CHECK(source_sequence>0),
 state TEXT NOT NULL DEFAULT 'pending' CHECK(state IN('pending','leased','delivered','dead_letter')),
 attempt_count INTEGER NOT NULL DEFAULT 0 CHECK(attempt_count>=0),
 next_attempt_at TEXT NOT NULL,
 lease_token TEXT,
 lease_until TEXT,
 delivered_at TEXT,
 last_error TEXT,
 PRIMARY KEY(target_database_id,event_id),
 UNIQUE(target_database_id,source_database_id,source_sequence),
 FOREIGN KEY(target_database_id) REFERENCES sync_delivery_peers(target_database_id) ON DELETE RESTRICT,
 FOREIGN KEY(event_id) REFERENCES sync_remote_event_projections(event_id) ON DELETE RESTRICT,
 CHECK(target_database_id<>source_database_id))
''');
  await db.customStatement('''
CREATE INDEX IF NOT EXISTS idx_sync_relay_deliveries_dispatch
ON sync_relay_deliveries(target_database_id,source_database_id,source_sequence,state,next_attempt_at)
''');
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS trg_sync_relay_delivery_no_delete BEFORE DELETE ON sync_relay_deliveries BEGIN SELECT RAISE(ABORT,'LAN relay delivery evidence cannot be deleted'); END",
  );
  await db.customStatement('''
CREATE TRIGGER IF NOT EXISTS trg_sync_relay_delivery_identity
BEFORE UPDATE ON sync_relay_deliveries
WHEN NEW.target_database_id IS NOT OLD.target_database_id
 OR NEW.event_id IS NOT OLD.event_id
 OR NEW.source_database_id IS NOT OLD.source_database_id
 OR NEW.source_sequence IS NOT OLD.source_sequence
BEGIN SELECT RAISE(ABORT,'LAN relay delivery identity is immutable'); END
''');
  await db.customStatement('''
CREATE TRIGGER IF NOT EXISTS trg_sync_relay_delivery_state
BEFORE UPDATE ON sync_relay_deliveries
WHEN NOT(
 (OLD.state IN('pending','leased') AND NEW.state='leased'
   AND NEW.attempt_count=OLD.attempt_count+1
   AND NEW.lease_token IS NOT NULL AND NEW.lease_until IS NOT NULL
   AND NEW.delivered_at IS NULL)
 OR(OLD.state='leased' AND NEW.state='delivered'
   AND NEW.attempt_count=OLD.attempt_count
   AND NEW.lease_token IS NULL AND NEW.lease_until IS NULL
   AND NEW.delivered_at IS NOT NULL)
 OR(OLD.state='leased' AND NEW.state IN('pending','dead_letter')
   AND NEW.attempt_count=OLD.attempt_count
   AND NEW.lease_token IS NULL AND NEW.lease_until IS NULL
   AND NEW.delivered_at IS NULL
   AND (NEW.state<>'dead_letter' OR NEW.last_error IS NOT NULL))
)
BEGIN SELECT RAISE(ABORT,'Invalid LAN relay delivery transition'); END
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

  // Categories, colours and sizes also need stable identities. They are kept
  // separate from financial parties so an older generic identity table does
  // not need a destructive CHECK-constraint rebuild.
  await db.customStatement('''
CREATE TABLE IF NOT EXISTS sync_catalogue_dimension_identities(
 entity_type TEXT NOT NULL CHECK(entity_type IN('category','color','size')),
 local_id INTEGER NOT NULL CHECK(local_id>0),
 global_id TEXT NOT NULL CHECK(length(global_id)=36),
 origin_database_id TEXT NOT NULL CHECK(length(origin_database_id)=36),
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 PRIMARY KEY(entity_type,local_id), UNIQUE(entity_type,global_id))
''');
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS trg_sync_catalogue_dimension_no_delete BEFORE DELETE ON sync_catalogue_dimension_identities BEGIN SELECT RAISE(ABORT,'Catalogue dimension identity cannot be deleted'); END",
  );
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS trg_sync_catalogue_dimension_no_update BEFORE UPDATE ON sync_catalogue_dimension_identities BEGIN SELECT RAISE(ABORT,'Catalogue dimension identity is immutable'); END",
  );
  await db.customStatement('''
CREATE TRIGGER IF NOT EXISTS trg_sync_catalogue_dimension_target
BEFORE INSERT ON sync_catalogue_dimension_identities
WHEN (NEW.entity_type='category' AND NOT EXISTS(SELECT 1 FROM product_categories WHERE id=NEW.local_id))
 OR (NEW.entity_type='color' AND NOT EXISTS(SELECT 1 FROM product_colors WHERE id=NEW.local_id))
 OR (NEW.entity_type='size' AND NOT EXISTS(SELECT 1 FROM sizes WHERE id=NEW.local_id))
BEGIN SELECT RAISE(ABORT,'Catalogue dimension target does not exist'); END
''');
  await _ensureCataloguePageTypes(db);
  await db.customStatement('''
CREATE TABLE IF NOT EXISTS sync_catalogue_pages(
 event_id TEXT PRIMARY KEY CHECK(length(event_id)=36),
 snapshot_id TEXT NOT NULL CHECK(length(snapshot_id)=36),
 entity_type TEXT NOT NULL CHECK(entity_type IN('supplier','customer','category','color','size','product','variant','promotion')),
 page_index INTEGER NOT NULL CHECK(page_index>=0),
 page_count INTEGER NOT NULL CHECK(page_count>0 AND page_index<page_count),
 source_database_id TEXT NOT NULL CHECK(length(source_database_id)=36),
 applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE(snapshot_id,entity_type,page_index),
 FOREIGN KEY(event_id) REFERENCES sync_inbox_receipts(event_id) ON DELETE RESTRICT)
''');
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS trg_sync_catalogue_page_no_delete BEFORE DELETE ON sync_catalogue_pages BEGIN SELECT RAISE(ABORT,'Catalogue synchronization evidence cannot be deleted'); END",
  );
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS trg_sync_catalogue_page_no_update BEFORE UPDATE ON sync_catalogue_pages BEGIN SELECT RAISE(ABORT,'Catalogue synchronization evidence is immutable'); END",
  );

  // Shared location directory. These rows describe routing only and never
  // create local stock balances or change this database's business_context.
  await db.customStatement('''
CREATE TABLE IF NOT EXISTS sync_branch_directory(
 branch_id TEXT PRIMARY KEY CHECK(length(branch_id)=36),
 organization_id TEXT NOT NULL CHECK(length(organization_id)=36),
 code TEXT NOT NULL,
 name TEXT NOT NULL,
 writer_database_id TEXT CHECK(writer_database_id IS NULL OR length(writer_database_id)=36),
 is_active INTEGER NOT NULL CHECK(is_active IN(0,1)),
 updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)
''');
  await db.customStatement('''
CREATE TABLE IF NOT EXISTS sync_warehouse_directory(
 warehouse_id TEXT PRIMARY KEY CHECK(length(warehouse_id)=36),
 organization_id TEXT NOT NULL CHECK(length(organization_id)=36),
 branch_id TEXT NOT NULL CHECK(length(branch_id)=36),
 code TEXT NOT NULL,
 name TEXT NOT NULL,
 location_kind TEXT NOT NULL DEFAULT 'warehouse'
   CHECK(location_kind IN('branch_store','warehouse')),
 is_active INTEGER NOT NULL CHECK(is_active IN(0,1)),
 updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 FOREIGN KEY(branch_id) REFERENCES sync_branch_directory(branch_id) ON DELETE RESTRICT)
''');
  final warehouseDirectoryColumns = await db
      .customSelect("PRAGMA table_info('sync_warehouse_directory')")
      .get();
  if (!warehouseDirectoryColumns.any(
    (row) => row.read<String>('name') == 'location_kind',
  )) {
    await db.customStatement(
      """ALTER TABLE sync_warehouse_directory ADD COLUMN location_kind
TEXT NOT NULL DEFAULT 'warehouse'
CHECK(location_kind IN('branch_store','warehouse'))""",
    );
  }
  await db.customStatement('''
CREATE TABLE IF NOT EXISTS sync_location_pages(
 event_id TEXT PRIMARY KEY CHECK(length(event_id)=36),
 snapshot_id TEXT NOT NULL CHECK(length(snapshot_id)=36),
 entity_type TEXT NOT NULL CHECK(entity_type IN('branch','warehouse')),
 page_index INTEGER NOT NULL CHECK(page_index>=0),
 page_count INTEGER NOT NULL CHECK(page_count>0 AND page_index<page_count),
 source_database_id TEXT NOT NULL CHECK(length(source_database_id)=36),
 applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE(snapshot_id,entity_type,page_index),
 FOREIGN KEY(event_id) REFERENCES sync_inbox_receipts(event_id) ON DELETE RESTRICT)
''');
  await db.customStatement('''
CREATE TRIGGER IF NOT EXISTS trg_sync_branch_directory_identity
BEFORE UPDATE ON sync_branch_directory
WHEN NEW.branch_id IS NOT OLD.branch_id OR NEW.organization_id IS NOT OLD.organization_id
BEGIN SELECT RAISE(ABORT,'Branch directory identity is immutable'); END
''');
  await db.customStatement('''
CREATE TRIGGER IF NOT EXISTS trg_sync_warehouse_directory_identity
BEFORE UPDATE ON sync_warehouse_directory
WHEN NEW.warehouse_id IS NOT OLD.warehouse_id
 OR NEW.organization_id IS NOT OLD.organization_id
 OR NEW.branch_id IS NOT OLD.branch_id
BEGIN SELECT RAISE(ABORT,'Warehouse directory identity is immutable'); END
''');
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS trg_sync_branch_directory_no_delete BEFORE DELETE ON sync_branch_directory BEGIN SELECT RAISE(ABORT,'Branch directory cannot be deleted'); END",
  );
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS trg_sync_warehouse_directory_no_delete BEFORE DELETE ON sync_warehouse_directory BEGIN SELECT RAISE(ABORT,'Warehouse directory cannot be deleted'); END",
  );
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS trg_sync_location_page_no_update BEFORE UPDATE ON sync_location_pages BEGIN SELECT RAISE(ABORT,'Location synchronization evidence is immutable'); END",
  );
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS trg_sync_location_page_no_delete BEFORE DELETE ON sync_location_pages BEGIN SELECT RAISE(ABORT,'Location synchronization evidence cannot be deleted'); END",
  );

  // A foreign dispatch is evidence only until its catalogue identities are
  // mapped and an authorized user posts a destination receipt.
  await db.customStatement('''
CREATE TABLE IF NOT EXISTS distributed_transfer_inbound_dispatches(
 transfer_id TEXT PRIMARY KEY CHECK(length(transfer_id)=36),
 dispatch_event_id TEXT NOT NULL UNIQUE CHECK(length(dispatch_event_id)=36),
 organization_id TEXT NOT NULL CHECK(length(organization_id)=36),
 source_database_id TEXT NOT NULL CHECK(length(source_database_id)=36),
 source_branch_id TEXT NOT NULL CHECK(length(source_branch_id)=36),
 source_warehouse_id TEXT NOT NULL CHECK(length(source_warehouse_id)=36),
 destination_branch_id TEXT NOT NULL CHECK(length(destination_branch_id)=36),
 destination_warehouse_id TEXT NOT NULL CHECK(length(destination_warehouse_id)=36),
 currency_code TEXT NOT NULL CHECK(length(currency_code)=3),
 dispatched_at TEXT NOT NULL,
 allocation_count INTEGER NOT NULL CHECK(allocation_count BETWEEN 1 AND 5000),
 owned_value_minor INTEGER NOT NULL CHECK(owned_value_minor>=0),
 payload_json TEXT NOT NULL CHECK(json_valid(payload_json)),
 payload_hash TEXT NOT NULL CHECK(length(payload_hash)=64),
 catalogue_state TEXT NOT NULL CHECK(catalogue_state IN('ready','awaiting_catalogue')),
 lifecycle_state TEXT NOT NULL DEFAULT 'awaiting_receipt'
   CHECK(lifecycle_state IN('awaiting_receipt','partially_received','completed','recalled','conflict')),
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 FOREIGN KEY(dispatch_event_id) REFERENCES sync_inbox_receipts(event_id) ON DELETE RESTRICT)
''');
  await db.customStatement('''
CREATE TABLE IF NOT EXISTS distributed_transfer_inbound_allocations(
 allocation_id TEXT PRIMARY KEY CHECK(length(allocation_id)=36),
 transfer_id TEXT NOT NULL,
 sequence INTEGER NOT NULL CHECK(sequence BETWEEN 1 AND 5000),
 product_global_id TEXT NOT NULL CHECK(length(product_global_id)=36),
 variant_global_id TEXT NOT NULL CHECK(length(variant_global_id)=36),
 owner_type TEXT NOT NULL CHECK(owner_type IN('owned','consignment')),
 quantity_scaled INTEGER NOT NULL CHECK(quantity_scaled>0),
 quantity_scale INTEGER NOT NULL CHECK(quantity_scale IN(1,1000)),
 measurement_type TEXT NOT NULL CHECK(measurement_type IN('piece','weight','length','volume')),
 unit_cost_minor INTEGER NOT NULL CHECK(unit_cost_minor>=0),
 value_minor INTEGER NOT NULL CHECK(value_minor>=0),
 supplier_global_id TEXT,
 consignment_agreement_id TEXT,
 source_consignment_layer_id TEXT,
 source_batch_json TEXT CHECK(source_batch_json IS NULL OR json_valid(source_batch_json)),
 origin_slices_json TEXT CHECK(origin_slices_json IS NULL OR json_valid(origin_slices_json)),
 consignment_terms_json TEXT CHECK(consignment_terms_json IS NULL OR json_valid(consignment_terms_json)),
 manufacturer_lot_number TEXT,
 expiry_date TEXT,
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE(transfer_id,sequence),
 FOREIGN KEY(transfer_id) REFERENCES distributed_transfer_inbound_dispatches(transfer_id) ON DELETE RESTRICT,
 CHECK((owner_type='owned' AND consignment_agreement_id IS NULL
   AND source_consignment_layer_id IS NULL)
  OR(owner_type='consignment' AND supplier_global_id IS NOT NULL
   AND consignment_agreement_id IS NOT NULL AND source_consignment_layer_id IS NOT NULL
   AND value_minor=0)))
''');
  final inboundAllocationColumns = await db
      .customSelect(
        'PRAGMA table_info(distributed_transfer_inbound_allocations)',
      )
      .get();
  if (!inboundAllocationColumns.any(
    (row) => row.read<String>('name') == 'consignment_terms_json',
  )) {
    await db.customStatement(
      'ALTER TABLE distributed_transfer_inbound_allocations '
      'ADD COLUMN consignment_terms_json TEXT '
      'CHECK(consignment_terms_json IS NULL OR json_valid(consignment_terms_json))',
    );
  }
  await db.customStatement('''
CREATE INDEX IF NOT EXISTS idx_distributed_transfer_inbound_status
ON distributed_transfer_inbound_dispatches(destination_warehouse_id,lifecycle_state,catalogue_state,dispatched_at)
''');
  await db.customStatement('''
CREATE TABLE IF NOT EXISTS distributed_transfer_inbound_receipts(
 receipt_id TEXT PRIMARY KEY CHECK(length(receipt_id)=36),
 transfer_id TEXT NOT NULL,
 request_key TEXT NOT NULL UNIQUE CHECK(length(request_key)=36),
 request_hash TEXT NOT NULL CHECK(length(request_hash)=64),
 actor_id INTEGER NOT NULL,
 item_count INTEGER NOT NULL CHECK(item_count BETWEEN 1 AND 5000),
 accepted_owned_value_minor INTEGER NOT NULL CHECK(accepted_owned_value_minor>=0),
 variance_owned_value_minor INTEGER NOT NULL CHECK(variance_owned_value_minor>=0),
 journal_entry_id INTEGER,
 notes TEXT NOT NULL DEFAULT '' CHECK(length(notes)<=500),
 received_at TEXT NOT NULL,
 sealed INTEGER NOT NULL DEFAULT 0 CHECK(sealed IN(0,1)),
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 FOREIGN KEY(transfer_id) REFERENCES distributed_transfer_inbound_dispatches(transfer_id) ON DELETE RESTRICT,
 FOREIGN KEY(actor_id) REFERENCES users(id) ON DELETE RESTRICT,
 FOREIGN KEY(journal_entry_id) REFERENCES journal_entries(id) ON DELETE RESTRICT)
''');
  await db.customStatement('''
CREATE TABLE IF NOT EXISTS distributed_transfer_inbound_receipt_items(
 item_id TEXT PRIMARY KEY CHECK(length(item_id)=36),
 receipt_id TEXT NOT NULL,
 allocation_id TEXT NOT NULL,
 accepted_quantity INTEGER NOT NULL DEFAULT 0 CHECK(accepted_quantity>=0),
 damaged_quantity INTEGER NOT NULL DEFAULT 0 CHECK(damaged_quantity>=0),
 lost_quantity INTEGER NOT NULL DEFAULT 0 CHECK(lost_quantity>=0),
 accepted_value_minor INTEGER NOT NULL DEFAULT 0 CHECK(accepted_value_minor>=0),
 variance_value_minor INTEGER NOT NULL DEFAULT 0 CHECK(variance_value_minor>=0),
 destination_batch_id INTEGER,
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE(receipt_id,allocation_id),
 CHECK(accepted_quantity+damaged_quantity+lost_quantity>0),
 FOREIGN KEY(receipt_id) REFERENCES distributed_transfer_inbound_receipts(receipt_id) ON DELETE RESTRICT,
 FOREIGN KEY(allocation_id) REFERENCES distributed_transfer_inbound_allocations(allocation_id) ON DELETE RESTRICT,
 FOREIGN KEY(destination_batch_id) REFERENCES product_batches(id) ON DELETE RESTRICT)
''');
  await db.customStatement('''
CREATE TABLE IF NOT EXISTS distributed_transfer_batch_links(
 destination_batch_id INTEGER PRIMARY KEY,
 allocation_id TEXT NOT NULL,
 receipt_item_id TEXT NOT NULL UNIQUE,
 source_batch_global_id TEXT,
 source_batch_database_id TEXT,
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 FOREIGN KEY(destination_batch_id) REFERENCES product_batches(id) ON DELETE RESTRICT,
 FOREIGN KEY(allocation_id) REFERENCES distributed_transfer_inbound_allocations(allocation_id) ON DELETE RESTRICT,
 FOREIGN KEY(receipt_item_id) REFERENCES distributed_transfer_inbound_receipt_items(item_id) ON DELETE RESTRICT)
''');
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS trg_distributed_receipt_no_delete BEFORE DELETE ON distributed_transfer_inbound_receipts BEGIN SELECT RAISE(ABORT,'Distributed transfer receipt cannot be deleted'); END",
  );
  await db.customStatement('''
CREATE TRIGGER IF NOT EXISTS trg_distributed_receipt_finalize
BEFORE UPDATE ON distributed_transfer_inbound_receipts
WHEN NOT(OLD.sealed=0 AND NEW.sealed=1
 AND NEW.receipt_id IS OLD.receipt_id AND NEW.transfer_id IS OLD.transfer_id
 AND NEW.request_key IS OLD.request_key AND NEW.request_hash IS OLD.request_hash
 AND NEW.actor_id=OLD.actor_id AND NEW.item_count=OLD.item_count
 AND NEW.accepted_owned_value_minor=OLD.accepted_owned_value_minor
 AND NEW.variance_owned_value_minor=OLD.variance_owned_value_minor
 AND NEW.notes IS OLD.notes AND NEW.received_at IS OLD.received_at
 AND NEW.created_at IS OLD.created_at)
BEGIN SELECT RAISE(ABORT,'Invalid distributed receipt finalization'); END
''');
  for (final table in const [
    'distributed_transfer_inbound_receipt_items',
    'distributed_transfer_batch_links',
  ]) {
    await db.customStatement(
      "CREATE TRIGGER IF NOT EXISTS trg_${table}_no_update BEFORE UPDATE ON $table BEGIN SELECT RAISE(ABORT,'Distributed receipt evidence is immutable'); END",
    );
    await db.customStatement(
      "CREATE TRIGGER IF NOT EXISTS trg_${table}_no_delete BEFORE DELETE ON $table BEGIN SELECT RAISE(ABORT,'Distributed receipt evidence cannot be deleted'); END",
    );
  }
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS trg_distributed_transfer_dispatch_no_delete BEFORE DELETE ON distributed_transfer_inbound_dispatches BEGIN SELECT RAISE(ABORT,'Distributed transfer dispatch evidence cannot be deleted'); END",
  );
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS trg_distributed_transfer_allocation_no_delete BEFORE DELETE ON distributed_transfer_inbound_allocations BEGIN SELECT RAISE(ABORT,'Distributed transfer allocation evidence cannot be deleted'); END",
  );
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS trg_distributed_transfer_allocation_no_update BEFORE UPDATE ON distributed_transfer_inbound_allocations BEGIN SELECT RAISE(ABORT,'Distributed transfer allocation is immutable'); END",
  );
  await db.customStatement('''
CREATE TRIGGER IF NOT EXISTS trg_distributed_transfer_dispatch_update
BEFORE UPDATE ON distributed_transfer_inbound_dispatches
WHEN NEW.transfer_id IS NOT OLD.transfer_id
 OR NEW.dispatch_event_id IS NOT OLD.dispatch_event_id
 OR NEW.organization_id IS NOT OLD.organization_id
 OR NEW.source_database_id IS NOT OLD.source_database_id
 OR NEW.source_branch_id IS NOT OLD.source_branch_id
 OR NEW.source_warehouse_id IS NOT OLD.source_warehouse_id
 OR NEW.destination_branch_id IS NOT OLD.destination_branch_id
 OR NEW.destination_warehouse_id IS NOT OLD.destination_warehouse_id
 OR NEW.currency_code IS NOT OLD.currency_code
 OR NEW.dispatched_at IS NOT OLD.dispatched_at
 OR NEW.allocation_count IS NOT OLD.allocation_count
 OR NEW.owned_value_minor IS NOT OLD.owned_value_minor
 OR NEW.payload_json IS NOT OLD.payload_json
 OR NEW.payload_hash IS NOT OLD.payload_hash
 OR NEW.created_at IS NOT OLD.created_at
 OR NOT(
   (NEW.catalogue_state=OLD.catalogue_state OR
     (OLD.catalogue_state='awaiting_catalogue' AND NEW.catalogue_state='ready'))
   AND (NEW.lifecycle_state=OLD.lifecycle_state
     OR (OLD.lifecycle_state='awaiting_receipt' AND NEW.lifecycle_state IN('partially_received','completed','recalled','conflict'))
     OR (OLD.lifecycle_state='partially_received' AND NEW.lifecycle_state IN('completed','conflict')))
 )
BEGIN SELECT RAISE(ABORT,'Invalid distributed transfer state transition'); END
''');

  // Destination acknowledgements remain immutable and are reconciled at the
  // source without importing a journal entry owned by another database.
  await db.customStatement('''
CREATE TABLE IF NOT EXISTS distributed_transfer_remote_events(
 event_id TEXT PRIMARY KEY CHECK(length(event_id)=36),
 transfer_id TEXT NOT NULL CHECK(length(transfer_id)=36),
 event_type TEXT NOT NULL CHECK(event_type IN('warehouse_transfer.received.v1','warehouse_transfer.recalled.v1')),
 source_database_id TEXT NOT NULL CHECK(length(source_database_id)=36),
 source_branch_id TEXT NOT NULL CHECK(length(source_branch_id)=36),
 local_warehouse_id TEXT NOT NULL CHECK(length(local_warehouse_id)=36),
 payload_json TEXT NOT NULL CHECK(json_valid(payload_json)),
 payload_hash TEXT NOT NULL CHECK(length(payload_hash)=64),
 occurred_at TEXT NOT NULL,
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE(transfer_id,event_type,event_id),
 FOREIGN KEY(event_id) REFERENCES sync_inbox_receipts(event_id) ON DELETE RESTRICT)
''');
  await db.customStatement('''
CREATE TABLE IF NOT EXISTS distributed_transfer_source_receipt_items(
 event_id TEXT NOT NULL,
 allocation_id TEXT NOT NULL,
 accepted_quantity INTEGER NOT NULL DEFAULT 0 CHECK(accepted_quantity>=0),
 damaged_quantity INTEGER NOT NULL DEFAULT 0 CHECK(damaged_quantity>=0),
 lost_quantity INTEGER NOT NULL DEFAULT 0 CHECK(lost_quantity>=0),
 accepted_value_minor INTEGER NOT NULL DEFAULT 0 CHECK(accepted_value_minor>=0),
 variance_value_minor INTEGER NOT NULL DEFAULT 0 CHECK(variance_value_minor>=0),
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 PRIMARY KEY(event_id,allocation_id),
 CHECK(accepted_quantity+damaged_quantity+lost_quantity>0),
 FOREIGN KEY(event_id) REFERENCES distributed_transfer_remote_events(event_id) ON DELETE RESTRICT,
 FOREIGN KEY(allocation_id) REFERENCES warehouse_transfer_allocations(id) ON DELETE RESTRICT)
''');
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS trg_distributed_transfer_remote_event_no_delete BEFORE DELETE ON distributed_transfer_remote_events BEGIN SELECT RAISE(ABORT,'Distributed transfer acknowledgement cannot be deleted'); END",
  );
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS trg_distributed_transfer_remote_event_no_update BEFORE UPDATE ON distributed_transfer_remote_events BEGIN SELECT RAISE(ABORT,'Distributed transfer acknowledgement is immutable'); END",
  );
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS trg_distributed_source_receipt_item_no_delete BEFORE DELETE ON distributed_transfer_source_receipt_items BEGIN SELECT RAISE(ABORT,'Distributed transfer receipt item cannot be deleted'); END",
  );
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS trg_distributed_source_receipt_item_no_update BEFORE UPDATE ON distributed_transfer_source_receipt_items BEGIN SELECT RAISE(ABORT,'Distributed transfer receipt item is immutable'); END",
  );

  // Cross-database outbound documents cannot use warehouse_transfers because
  // that table intentionally binds both warehouses to one local branch. This
  // ledger preserves the reviewed source intent and its frozen dispatch while
  // the destination remains a directory identity owned by another database.
  await db.customStatement('''
CREATE TABLE IF NOT EXISTS distributed_transfer_outbound_documents(
 transfer_id TEXT PRIMARY KEY CHECK(length(transfer_id)=36),
 organization_id TEXT NOT NULL CHECK(length(organization_id)=36),
 source_database_id TEXT NOT NULL CHECK(length(source_database_id)=36),
 source_branch_id TEXT NOT NULL CHECK(length(source_branch_id)=36),
 source_warehouse_id TEXT NOT NULL CHECK(length(source_warehouse_id)=36),
 destination_database_id TEXT NOT NULL CHECK(length(destination_database_id)=36),
 destination_branch_id TEXT NOT NULL CHECK(length(destination_branch_id)=36),
 destination_warehouse_id TEXT NOT NULL CHECK(length(destination_warehouse_id)=36),
 currency_id INTEGER NOT NULL,
 currency_code TEXT NOT NULL CHECK(length(currency_code)=3),
 created_by INTEGER NOT NULL,
 request_key TEXT NOT NULL UNIQUE CHECK(length(request_key)=36),
 request_hash TEXT NOT NULL CHECK(length(request_hash)=64),
 notes TEXT NOT NULL DEFAULT '' CHECK(length(notes)<=500),
 line_count INTEGER NOT NULL CHECK(line_count BETWEEN 1 AND 500),
 status TEXT NOT NULL DEFAULT 'draft'
   CHECK(status IN('draft','in_transit','partially_received','completed','cancelled','recalled','conflict')),
 created_at TEXT NOT NULL,
 updated_at TEXT NOT NULL,
 FOREIGN KEY(currency_id) REFERENCES currencies(id) ON DELETE RESTRICT,
 FOREIGN KEY(created_by) REFERENCES users(id) ON DELETE RESTRICT)
''');
  await db.customStatement('''
CREATE TABLE IF NOT EXISTS distributed_transfer_outbound_lines(
 line_id TEXT PRIMARY KEY CHECK(length(line_id)=36),
 transfer_id TEXT NOT NULL,
 product_id INTEGER NOT NULL,
 variant_id INTEGER NOT NULL,
 quantity_scaled INTEGER NOT NULL CHECK(quantity_scaled>0),
 quantity_scale INTEGER NOT NULL CHECK(quantity_scale IN(1,1000)),
 measurement_type TEXT NOT NULL CHECK(measurement_type IN('piece','weight','length','volume')),
 requested_owned_quantity INTEGER,
 requested_consignment_quantity INTEGER,
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE(transfer_id,variant_id),
 CHECK((requested_owned_quantity IS NULL AND requested_consignment_quantity IS NULL)
   OR(requested_owned_quantity>=0 AND requested_consignment_quantity>=0
    AND requested_owned_quantity+requested_consignment_quantity=quantity_scaled)),
 FOREIGN KEY(transfer_id) REFERENCES distributed_transfer_outbound_documents(transfer_id) ON DELETE RESTRICT,
 FOREIGN KEY(product_id) REFERENCES products(id) ON DELETE RESTRICT,
 FOREIGN KEY(variant_id) REFERENCES product_variants(id) ON DELETE RESTRICT)
''');
  await db.customStatement('''
CREATE TABLE IF NOT EXISTS distributed_transfer_outbound_dispatches(
 dispatch_id INTEGER PRIMARY KEY AUTOINCREMENT,
 transfer_id TEXT NOT NULL UNIQUE,
 request_key TEXT NOT NULL UNIQUE CHECK(length(request_key)=36),
 request_hash TEXT NOT NULL CHECK(length(request_hash)=64),
 actor_id INTEGER NOT NULL,
 allocation_count INTEGER NOT NULL CHECK(allocation_count BETWEEN 1 AND 5000),
 owned_value_minor INTEGER NOT NULL CHECK(owned_value_minor>=0),
 journal_entry_id INTEGER,
 payload_json TEXT NOT NULL CHECK(json_valid(payload_json)),
 payload_hash TEXT NOT NULL CHECK(length(payload_hash)=64),
 dispatched_at TEXT NOT NULL,
 sealed INTEGER NOT NULL DEFAULT 0 CHECK(sealed IN(0,1)),
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 FOREIGN KEY(transfer_id) REFERENCES distributed_transfer_outbound_documents(transfer_id) ON DELETE RESTRICT,
 FOREIGN KEY(actor_id) REFERENCES users(id) ON DELETE RESTRICT,
 FOREIGN KEY(journal_entry_id) REFERENCES journal_entries(id) ON DELETE RESTRICT)
''');
  await db.customStatement('''
CREATE TABLE IF NOT EXISTS distributed_transfer_outbound_allocations(
 allocation_id TEXT PRIMARY KEY CHECK(length(allocation_id)=36),
 dispatch_id INTEGER NOT NULL,
 line_id TEXT NOT NULL,
 sequence INTEGER NOT NULL CHECK(sequence BETWEEN 1 AND 5000),
 owner_type TEXT NOT NULL CHECK(owner_type IN('owned','consignment')),
 quantity_scaled INTEGER NOT NULL CHECK(quantity_scaled>0),
 quantity_scale INTEGER NOT NULL CHECK(quantity_scale IN(1,1000)),
 measurement_type TEXT NOT NULL CHECK(measurement_type IN('piece','weight','length','volume')),
 unit_cost_minor INTEGER NOT NULL CHECK(unit_cost_minor>=0),
 value_minor INTEGER NOT NULL CHECK(value_minor>=0),
 source_batch_id INTEGER,
 source_consignment_layer_id TEXT,
 supplier_id INTEGER,
 agreement_id TEXT,
 manufacturer_lot_number TEXT,
 expiry_date TEXT,
 origin_slices_json TEXT CHECK(origin_slices_json IS NULL OR json_valid(origin_slices_json)),
 consignment_terms_json TEXT CHECK(consignment_terms_json IS NULL OR json_valid(consignment_terms_json)),
 UNIQUE(dispatch_id,sequence),
 CHECK((owner_type='owned' AND source_consignment_layer_id IS NULL AND agreement_id IS NULL)
   OR(owner_type='consignment' AND source_consignment_layer_id IS NOT NULL
    AND supplier_id IS NOT NULL AND agreement_id IS NOT NULL AND value_minor=0
    AND consignment_terms_json IS NOT NULL)),
 FOREIGN KEY(dispatch_id) REFERENCES distributed_transfer_outbound_dispatches(dispatch_id) ON DELETE RESTRICT,
 FOREIGN KEY(line_id) REFERENCES distributed_transfer_outbound_lines(line_id) ON DELETE RESTRICT,
 FOREIGN KEY(source_batch_id) REFERENCES product_batches(id) ON DELETE RESTRICT,
 FOREIGN KEY(source_consignment_layer_id) REFERENCES consignment_inventory_layers(id) ON DELETE RESTRICT,
 FOREIGN KEY(supplier_id) REFERENCES suppliers(id) ON DELETE RESTRICT,
 FOREIGN KEY(agreement_id) REFERENCES consignment_agreements(id) ON DELETE RESTRICT)
''');
  await db.customStatement('''
CREATE TABLE IF NOT EXISTS distributed_transfer_outbound_batch_links(
 allocation_id TEXT PRIMARY KEY,
 consumption_id INTEGER NOT NULL UNIQUE,
 FOREIGN KEY(allocation_id) REFERENCES distributed_transfer_outbound_allocations(allocation_id) ON DELETE RESTRICT,
 FOREIGN KEY(consumption_id) REFERENCES batch_consumptions(id) ON DELETE RESTRICT)
''');
  await db.customStatement('''
CREATE TABLE IF NOT EXISTS distributed_transfer_outbound_recalls(
 recall_id TEXT PRIMARY KEY CHECK(length(recall_id)=36),
 transfer_id TEXT NOT NULL UNIQUE,
 request_key TEXT NOT NULL UNIQUE CHECK(length(request_key)=36),
 request_hash TEXT NOT NULL CHECK(length(request_hash)=64),
 actor_id INTEGER NOT NULL,
 reason TEXT NOT NULL CHECK(length(trim(reason)) BETWEEN 1 AND 500),
 journal_entry_id INTEGER,
 recalled_at TEXT NOT NULL,
 sealed INTEGER NOT NULL DEFAULT 0 CHECK(sealed IN(0,1)),
 FOREIGN KEY(transfer_id) REFERENCES distributed_transfer_outbound_documents(transfer_id) ON DELETE RESTRICT,
 FOREIGN KEY(actor_id) REFERENCES users(id) ON DELETE RESTRICT,
 FOREIGN KEY(journal_entry_id) REFERENCES journal_entries(id) ON DELETE RESTRICT)
''');
  await db.customStatement('''
CREATE TABLE IF NOT EXISTS distributed_transfer_outbound_recall_requests(
 request_id TEXT PRIMARY KEY CHECK(length(request_id)=36),
 transfer_id TEXT NOT NULL UNIQUE,
 request_key TEXT NOT NULL UNIQUE CHECK(length(request_key)=36),
 request_hash TEXT NOT NULL CHECK(length(request_hash)=64),
 actor_id INTEGER NOT NULL,
 reason TEXT NOT NULL CHECK(length(trim(reason)) BETWEEN 1 AND 500),
 status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN('pending','accepted','rejected')),
 response_event_id TEXT,
 requested_at TEXT NOT NULL,
 resolved_at TEXT,
 FOREIGN KEY(transfer_id) REFERENCES distributed_transfer_outbound_documents(transfer_id) ON DELETE RESTRICT,
 FOREIGN KEY(actor_id) REFERENCES users(id) ON DELETE RESTRICT,
 CHECK((status='pending' AND response_event_id IS NULL AND resolved_at IS NULL)
   OR(status IN('accepted','rejected') AND response_event_id IS NOT NULL AND resolved_at IS NOT NULL)))
''');
  await db.customStatement('''
CREATE TRIGGER IF NOT EXISTS trg_distributed_recall_request_update
BEFORE UPDATE ON distributed_transfer_outbound_recall_requests
WHEN NOT(OLD.status='pending' AND NEW.status IN('accepted','rejected')
 AND NEW.request_id=OLD.request_id AND NEW.transfer_id=OLD.transfer_id
 AND NEW.request_key=OLD.request_key AND NEW.request_hash=OLD.request_hash
 AND NEW.actor_id=OLD.actor_id AND NEW.reason=OLD.reason
 AND NEW.requested_at=OLD.requested_at
 AND NEW.response_event_id IS NOT NULL AND NEW.resolved_at IS NOT NULL)
BEGIN SELECT RAISE(ABORT,'Invalid distributed recall request resolution'); END
''');
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS trg_distributed_recall_request_no_delete BEFORE DELETE ON distributed_transfer_outbound_recall_requests BEGIN SELECT RAISE(ABORT,'Distributed recall request cannot be deleted'); END",
  );
  await db.customStatement('''
CREATE TABLE IF NOT EXISTS distributed_outbound_source_receipt_items(
 event_id TEXT NOT NULL,
 allocation_id TEXT NOT NULL,
 accepted_quantity INTEGER NOT NULL DEFAULT 0 CHECK(accepted_quantity>=0),
 damaged_quantity INTEGER NOT NULL DEFAULT 0 CHECK(damaged_quantity>=0),
 lost_quantity INTEGER NOT NULL DEFAULT 0 CHECK(lost_quantity>=0),
 accepted_value_minor INTEGER NOT NULL DEFAULT 0 CHECK(accepted_value_minor>=0),
 variance_value_minor INTEGER NOT NULL DEFAULT 0 CHECK(variance_value_minor>=0),
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 PRIMARY KEY(event_id,allocation_id),
 CHECK(accepted_quantity+damaged_quantity+lost_quantity>0),
 FOREIGN KEY(event_id) REFERENCES distributed_transfer_remote_events(event_id) ON DELETE RESTRICT,
 FOREIGN KEY(allocation_id) REFERENCES distributed_transfer_outbound_allocations(allocation_id) ON DELETE RESTRICT)
''');
  await db.customStatement('''
CREATE TABLE IF NOT EXISTS distributed_consignment_agreement_mirrors(
 source_database_id TEXT NOT NULL CHECK(length(source_database_id)=36),
 source_agreement_id TEXT NOT NULL CHECK(length(source_agreement_id)=36),
 local_agreement_id TEXT NOT NULL UNIQUE CHECK(length(local_agreement_id)=36),
 terms_hash TEXT NOT NULL CHECK(length(terms_hash)=64),
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 PRIMARY KEY(source_database_id,source_agreement_id),
 FOREIGN KEY(local_agreement_id) REFERENCES consignment_agreements(id) ON DELETE RESTRICT)
''');
  await db.customStatement('''
CREATE TABLE IF NOT EXISTS distributed_consignment_layer_links(
 allocation_id TEXT NOT NULL,
 receipt_item_id TEXT NOT NULL UNIQUE,
 layer_id TEXT NOT NULL UNIQUE,
 receipt_id TEXT NOT NULL,
 source_database_id TEXT NOT NULL CHECK(length(source_database_id)=36),
 source_layer_id TEXT NOT NULL CHECK(length(source_layer_id)=36),
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 PRIMARY KEY(allocation_id,receipt_item_id),
 FOREIGN KEY(allocation_id) REFERENCES distributed_transfer_inbound_allocations(allocation_id) ON DELETE RESTRICT,
 FOREIGN KEY(receipt_item_id) REFERENCES consignment_receipt_items(id) ON DELETE RESTRICT,
 FOREIGN KEY(layer_id) REFERENCES consignment_inventory_layers(id) ON DELETE RESTRICT,
 FOREIGN KEY(receipt_id) REFERENCES consignment_receipts(id) ON DELETE RESTRICT)
''');
  await db.customStatement('''
CREATE TRIGGER IF NOT EXISTS trg_distributed_outbound_document_update
BEFORE UPDATE ON distributed_transfer_outbound_documents
WHEN NEW.transfer_id IS NOT OLD.transfer_id
 OR NEW.organization_id IS NOT OLD.organization_id
 OR NEW.source_database_id IS NOT OLD.source_database_id
 OR NEW.source_branch_id IS NOT OLD.source_branch_id
 OR NEW.source_warehouse_id IS NOT OLD.source_warehouse_id
 OR NEW.destination_database_id IS NOT OLD.destination_database_id
 OR NEW.destination_branch_id IS NOT OLD.destination_branch_id
 OR NEW.destination_warehouse_id IS NOT OLD.destination_warehouse_id
 OR NEW.currency_id!=OLD.currency_id OR NEW.currency_code!=OLD.currency_code
 OR NEW.created_by!=OLD.created_by OR NEW.request_key!=OLD.request_key
 OR NEW.request_hash!=OLD.request_hash OR NEW.notes!=OLD.notes
 OR NEW.line_count!=OLD.line_count OR NEW.created_at!=OLD.created_at
 OR NOT(NEW.status=OLD.status
   OR(OLD.status='draft' AND NEW.status IN('in_transit','cancelled'))
   OR(OLD.status='in_transit' AND NEW.status IN('partially_received','completed','recalled','conflict'))
   OR(OLD.status='partially_received' AND NEW.status IN('completed','conflict')))
BEGIN SELECT RAISE(ABORT,'Invalid distributed outbound transition'); END
''');
  await db.customStatement('''
CREATE TRIGGER IF NOT EXISTS trg_distributed_outbound_dispatch_finalize
BEFORE UPDATE ON distributed_transfer_outbound_dispatches
WHEN NOT(OLD.sealed=0 AND NEW.sealed=1
 AND NEW.dispatch_id=OLD.dispatch_id AND NEW.transfer_id=OLD.transfer_id
 AND NEW.request_key=OLD.request_key AND NEW.request_hash=OLD.request_hash
 AND NEW.actor_id=OLD.actor_id AND NEW.allocation_count=OLD.allocation_count
 AND NEW.owned_value_minor=OLD.owned_value_minor
 AND NEW.dispatched_at=OLD.dispatched_at AND NEW.created_at=OLD.created_at)
BEGIN SELECT RAISE(ABORT,'Invalid distributed outbound finalization'); END
''');
  await db.customStatement('''
CREATE TRIGGER IF NOT EXISTS trg_distributed_outbound_recall_finalize
BEFORE UPDATE ON distributed_transfer_outbound_recalls
WHEN NOT(OLD.sealed=0 AND NEW.sealed=1
 AND NEW.recall_id=OLD.recall_id AND NEW.transfer_id=OLD.transfer_id
 AND NEW.request_key=OLD.request_key AND NEW.request_hash=OLD.request_hash
 AND NEW.actor_id=OLD.actor_id AND NEW.reason=OLD.reason
 AND NEW.recalled_at=OLD.recalled_at)
BEGIN SELECT RAISE(ABORT,'Invalid distributed recall finalization'); END
''');
  for (final table in const [
    'distributed_transfer_outbound_lines',
    'distributed_transfer_outbound_allocations',
    'distributed_transfer_outbound_batch_links',
    'distributed_outbound_source_receipt_items',
    'distributed_consignment_agreement_mirrors',
  ]) {
    await db.customStatement(
      "CREATE TRIGGER IF NOT EXISTS trg_${table}_no_update BEFORE UPDATE ON $table BEGIN SELECT RAISE(ABORT,'Distributed outbound evidence is immutable'); END",
    );
    await db.customStatement(
      "CREATE TRIGGER IF NOT EXISTS trg_${table}_no_delete BEFORE DELETE ON $table BEGIN SELECT RAISE(ABORT,'Distributed outbound evidence cannot be deleted'); END",
    );
  }
  for (final table in const [
    'distributed_transfer_outbound_documents',
    'distributed_transfer_outbound_dispatches',
    'distributed_transfer_outbound_recalls',
  ]) {
    await db.customStatement(
      "CREATE TRIGGER IF NOT EXISTS trg_${table}_no_delete BEFORE DELETE ON $table BEGIN SELECT RAISE(ABORT,'Distributed outbound evidence cannot be deleted'); END",
    );
  }
}

/// The synchronization ledger is an intentionally sidecar schema installed on
/// every open. Upgrade the immutable page ledger in place when an older build
/// predates shared customer identities. Rows and their event foreign keys are
/// copied byte-for-byte; no financial or inventory data is rewritten.
Future<void> _ensureCataloguePageTypes(AppDatabase db) async {
  final row = await db
      .customSelect(
        "SELECT sql FROM sqlite_master WHERE type='table' "
        "AND name='sync_catalogue_pages'",
      )
      .getSingleOrNull();
  final sql = row?.readNullable<String>('sql') ?? '';
  if (sql.isEmpty || sql.contains("'promotion'")) return;

  await db.transaction(() async {
    await db.customStatement(
      'DROP TRIGGER IF EXISTS trg_sync_catalogue_page_no_delete',
    );
    await db.customStatement(
      'DROP TRIGGER IF EXISTS trg_sync_catalogue_page_no_update',
    );
    await db.customStatement('''
CREATE TABLE sync_catalogue_pages_v2(
 event_id TEXT PRIMARY KEY CHECK(length(event_id)=36),
 snapshot_id TEXT NOT NULL CHECK(length(snapshot_id)=36),
 entity_type TEXT NOT NULL CHECK(entity_type IN('supplier','customer','category','color','size','product','variant','promotion')),
 page_index INTEGER NOT NULL CHECK(page_index>=0),
 page_count INTEGER NOT NULL CHECK(page_count>0 AND page_index<page_count),
 source_database_id TEXT NOT NULL CHECK(length(source_database_id)=36),
 applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE(snapshot_id,entity_type,page_index),
 FOREIGN KEY(event_id) REFERENCES sync_inbox_receipts(event_id) ON DELETE RESTRICT)
''');
    await db.customStatement('''
INSERT INTO sync_catalogue_pages_v2(
 event_id,snapshot_id,entity_type,page_index,page_count,source_database_id,applied_at)
SELECT event_id,snapshot_id,entity_type,page_index,page_count,source_database_id,applied_at
FROM sync_catalogue_pages
''');
    await db.customStatement('DROP TABLE sync_catalogue_pages');
    await db.customStatement(
      'ALTER TABLE sync_catalogue_pages_v2 RENAME TO sync_catalogue_pages',
    );
  });
}
