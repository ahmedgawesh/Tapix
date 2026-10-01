import '../app_database.dart';

/// Local-only coordinator registry for independent branch databases.
/// This is deliberately separate from cashier-device pairing and from the
/// paid online-branches entitlement.
Future<void> installLanBranchEnrollmentRegistry(AppDatabase db) async {
  await db.customStatement('''
CREATE TABLE IF NOT EXISTS lan_branch_coordinator_state(
 id INTEGER PRIMARY KEY CHECK(id=1),
 organization_id TEXT NOT NULL CHECK(length(organization_id)=36),
 database_id TEXT NOT NULL UNIQUE CHECK(length(database_id)=36),
 writer_enrollment_id TEXT NOT NULL UNIQUE CHECK(length(writer_enrollment_id)=36),
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)
''');
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS trg_lan_branch_coordinator_no_update BEFORE UPDATE ON lan_branch_coordinator_state BEGIN SELECT RAISE(ABORT,'LAN branch coordinator identity is immutable'); END",
  );
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS trg_lan_branch_coordinator_no_delete BEFORE DELETE ON lan_branch_coordinator_state BEGIN SELECT RAISE(ABORT,'LAN branch coordinator identity cannot be deleted'); END",
  );
  await db.customStatement('''
CREATE TRIGGER IF NOT EXISTS trg_lan_branch_coordinator_identity
BEFORE INSERT ON lan_branch_coordinator_state
WHEN NOT EXISTS(
 SELECT 1 FROM business_contexts c WHERE c.id=1
 AND c.organization_id=NEW.organization_id AND c.database_id=NEW.database_id)
BEGIN SELECT RAISE(ABORT,'LAN coordinator identity mismatch'); END
''');

  await db.customStatement('''
CREATE TABLE IF NOT EXISTS lan_branch_enrollments(
 enrollment_id TEXT PRIMARY KEY CHECK(length(enrollment_id)=36),
 organization_id TEXT NOT NULL CHECK(length(organization_id)=36),
 branch_id TEXT NOT NULL CHECK(length(branch_id)=36),
 warehouse_id TEXT NOT NULL CHECK(length(warehouse_id)=36),
 coordinator_database_id TEXT NOT NULL CHECK(length(coordinator_database_id)=36),
 secret_hash TEXT NOT NULL CHECK(length(secret_hash)=64),
 status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN('pending','active','revoked')),
 issued_by INTEGER NOT NULL,
 expires_at TEXT NOT NULL,
 remote_database_id TEXT UNIQUE,
 activated_at TEXT,
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CHECK((status='pending' AND remote_database_id IS NULL AND activated_at IS NULL)
 OR(status='active' AND remote_database_id IS NOT NULL AND activated_at IS NOT NULL)
 OR(status='revoked')),
 FOREIGN KEY(branch_id,organization_id) REFERENCES business_branches(id,organization_id) ON DELETE RESTRICT,
 FOREIGN KEY(warehouse_id,branch_id,organization_id) REFERENCES business_warehouses(id,branch_id,organization_id) ON DELETE RESTRICT,
 FOREIGN KEY(issued_by) REFERENCES users(id) ON DELETE RESTRICT)
''');
  await db.customStatement('''
CREATE TABLE IF NOT EXISTS lan_branch_sync_credentials(
 enrollment_id TEXT PRIMARY KEY,
 remote_database_id TEXT NOT NULL UNIQUE CHECK(length(remote_database_id)=36),
 token_hash TEXT NOT NULL CHECK(length(token_hash)=64),
 status TEXT NOT NULL DEFAULT 'active' CHECK(status IN('active','revoked')),
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 last_seen_at TEXT,
 FOREIGN KEY(enrollment_id) REFERENCES lan_branch_enrollments(enrollment_id) ON DELETE RESTRICT)
''');
  // Recovery rotates the network credential for an exact backup restore while
  // retaining the database/enrollment identity and its event sequence. The
  // original immutable credential remains as evidence and is revoked.
  await db.customStatement('''
CREATE TABLE IF NOT EXISTS lan_branch_recovery_challenges(
 challenge_id TEXT PRIMARY KEY CHECK(length(challenge_id)=36),
 enrollment_id TEXT NOT NULL,
 remote_database_id TEXT NOT NULL CHECK(length(remote_database_id)=36),
 secret_hash TEXT NOT NULL CHECK(length(secret_hash)=64),
 reason TEXT NOT NULL CHECK(length(trim(reason)) BETWEEN 1 AND 500),
 status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN('pending','used','revoked')),
 issued_by INTEGER NOT NULL,
 expires_at TEXT NOT NULL,
 used_at TEXT,
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 FOREIGN KEY(enrollment_id) REFERENCES lan_branch_enrollments(enrollment_id) ON DELETE RESTRICT,
 FOREIGN KEY(issued_by) REFERENCES users(id) ON DELETE RESTRICT,
 CHECK((status='pending' AND used_at IS NULL) OR(status='used' AND used_at IS NOT NULL) OR status='revoked'))
''');
  await db.customStatement('''
CREATE UNIQUE INDEX IF NOT EXISTS idx_lan_branch_pending_recovery
ON lan_branch_recovery_challenges(enrollment_id) WHERE status='pending'
''');
  await db.customStatement('''
CREATE TABLE IF NOT EXISTS lan_branch_recovery_credentials(
 challenge_id TEXT PRIMARY KEY,
 enrollment_id TEXT NOT NULL,
 remote_database_id TEXT NOT NULL CHECK(length(remote_database_id)=36),
 token_hash TEXT NOT NULL CHECK(length(token_hash)=64),
 generation INTEGER NOT NULL CHECK(generation>0),
 status TEXT NOT NULL DEFAULT 'active' CHECK(status IN('active','revoked')),
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 last_seen_at TEXT,
 FOREIGN KEY(challenge_id) REFERENCES lan_branch_recovery_challenges(challenge_id) ON DELETE RESTRICT,
 FOREIGN KEY(enrollment_id) REFERENCES lan_branch_enrollments(enrollment_id) ON DELETE RESTRICT)
''');
  await db.customStatement('''
CREATE UNIQUE INDEX IF NOT EXISTS idx_lan_branch_active_recovery_enrollment
ON lan_branch_recovery_credentials(enrollment_id) WHERE status='active'
''');
  await db.customStatement('''
CREATE UNIQUE INDEX IF NOT EXISTS idx_lan_branch_active_recovery_database
ON lan_branch_recovery_credentials(remote_database_id) WHERE status='active'
''');
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS trg_lan_branch_recovery_challenge_no_delete BEFORE DELETE ON lan_branch_recovery_challenges BEGIN SELECT RAISE(ABORT,'LAN branch recovery evidence cannot be deleted'); END",
  );
  await db.customStatement('''
CREATE TRIGGER IF NOT EXISTS trg_lan_branch_recovery_challenge_update
BEFORE UPDATE ON lan_branch_recovery_challenges
WHEN NEW.challenge_id IS NOT OLD.challenge_id
 OR NEW.enrollment_id IS NOT OLD.enrollment_id
 OR NEW.remote_database_id IS NOT OLD.remote_database_id
 OR NEW.secret_hash IS NOT OLD.secret_hash
 OR NEW.reason IS NOT OLD.reason
 OR NEW.issued_by IS NOT OLD.issued_by
 OR NEW.expires_at IS NOT OLD.expires_at
 OR NEW.created_at IS NOT OLD.created_at
 OR NOT((OLD.status='pending' AND NEW.status IN('used','revoked')))
 OR(NEW.status='used' AND NEW.used_at IS NULL)
BEGIN SELECT RAISE(ABORT,'Invalid LAN branch recovery transition'); END
''');
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS trg_lan_branch_recovery_credential_no_delete BEFORE DELETE ON lan_branch_recovery_credentials BEGIN SELECT RAISE(ABORT,'LAN branch recovery credential cannot be deleted'); END",
  );
  await db.customStatement('''
CREATE TRIGGER IF NOT EXISTS trg_lan_branch_recovery_credential_update
BEFORE UPDATE ON lan_branch_recovery_credentials
WHEN NEW.challenge_id IS NOT OLD.challenge_id
 OR NEW.enrollment_id IS NOT OLD.enrollment_id
 OR NEW.remote_database_id IS NOT OLD.remote_database_id
 OR NEW.token_hash IS NOT OLD.token_hash
 OR NEW.generation IS NOT OLD.generation
 OR NEW.created_at IS NOT OLD.created_at
 OR(OLD.status='revoked' AND NEW.status<>'revoked')
BEGIN SELECT RAISE(ABORT,'LAN branch recovery credential identity is immutable'); END
''');
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS trg_lan_branch_sync_credential_no_delete BEFORE DELETE ON lan_branch_sync_credentials BEGIN SELECT RAISE(ABORT,'LAN branch sync credential cannot be deleted'); END",
  );
  await db.customStatement('''
CREATE TRIGGER IF NOT EXISTS trg_lan_branch_sync_credential_identity
BEFORE UPDATE ON lan_branch_sync_credentials
WHEN NEW.enrollment_id IS NOT OLD.enrollment_id
 OR NEW.remote_database_id IS NOT OLD.remote_database_id
 OR NEW.token_hash IS NOT OLD.token_hash
 OR NEW.created_at IS NOT OLD.created_at
 OR(OLD.status='revoked' AND NEW.status<>'revoked')
BEGIN SELECT RAISE(ABORT,'LAN branch sync credential identity is immutable'); END
''');
  await db.customStatement('''
CREATE UNIQUE INDEX IF NOT EXISTS idx_lan_branch_pending_enrollment
ON lan_branch_enrollments(branch_id) WHERE status='pending'
''');
  await db.customStatement('''
CREATE UNIQUE INDEX IF NOT EXISTS idx_lan_branch_active_enrollment
ON lan_branch_enrollments(branch_id) WHERE status='active'
''');
  await db.customStatement(
    "CREATE TRIGGER IF NOT EXISTS trg_lan_branch_enrollment_no_delete BEFORE DELETE ON lan_branch_enrollments BEGIN SELECT RAISE(ABORT,'LAN branch enrollment evidence cannot be deleted'); END",
  );
  await db.customStatement('''
CREATE TRIGGER IF NOT EXISTS trg_lan_branch_enrollment_update
BEFORE UPDATE ON lan_branch_enrollments
WHEN NEW.enrollment_id IS NOT OLD.enrollment_id
 OR NEW.organization_id IS NOT OLD.organization_id
 OR NEW.branch_id IS NOT OLD.branch_id
 OR NEW.warehouse_id IS NOT OLD.warehouse_id
 OR NEW.coordinator_database_id IS NOT OLD.coordinator_database_id
 OR NEW.secret_hash IS NOT OLD.secret_hash
 OR NEW.issued_by IS NOT OLD.issued_by
 OR NEW.expires_at IS NOT OLD.expires_at
 OR NEW.created_at IS NOT OLD.created_at
 OR NOT((OLD.status='pending' AND NEW.status IN('active','revoked'))
   OR(OLD.status='active' AND NEW.status='revoked'))
 OR(NEW.status='active' AND (NEW.remote_database_id IS NULL OR NEW.activated_at IS NULL))
 OR(NEW.status='revoked' AND NEW.remote_database_id IS NOT OLD.remote_database_id)
BEGIN SELECT RAISE(ABORT,'Invalid LAN branch enrollment transition'); END
''');
}
