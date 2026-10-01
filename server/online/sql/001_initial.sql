-- Apply with a migration account. The HTTP process uses tapbix_online_app.
CREATE SCHEMA IF NOT EXISTS tapbix_online;
DO $$ BEGIN
 IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='tapbix_online_app') THEN
  CREATE ROLE tapbix_online_app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
 END IF;
END $$;
CREATE TABLE tapbix_online.organizations (
 id uuid PRIMARY KEY, name text NOT NULL, online_until timestamptz NOT NULL
);
CREATE TABLE tapbix_online.writers (
 organization_id uuid NOT NULL REFERENCES tapbix_online.organizations(id),
 database_id uuid NOT NULL, branch_id uuid NOT NULL, name text NOT NULL,
 next_sequence bigint NOT NULL DEFAULT 1 CHECK(next_sequence>0), active boolean NOT NULL DEFAULT true,
 PRIMARY KEY(organization_id,database_id), UNIQUE(organization_id,branch_id)
);
CREATE TABLE tapbix_online.credentials (
 organization_id uuid NOT NULL, token_hash text NOT NULL, database_id uuid NOT NULL,
 role text NOT NULL CHECK(role IN ('owner','writer')), active boolean NOT NULL DEFAULT true,
 PRIMARY KEY(organization_id,token_hash),
 FOREIGN KEY(organization_id,database_id) REFERENCES tapbix_online.writers
);
CREATE TABLE tapbix_online.invitations (
 organization_id uuid NOT NULL REFERENCES tapbix_online.organizations(id),
 code_hash text NOT NULL, branch_id uuid NOT NULL, database_id uuid NOT NULL,
 name text NOT NULL, expires_at timestamptz NOT NULL, consumed boolean NOT NULL DEFAULT false,
 PRIMARY KEY(organization_id,code_hash)
);
CREATE TABLE tapbix_online.events (
 organization_id uuid NOT NULL, event_id uuid NOT NULL, source_database_id uuid NOT NULL,
 sequence bigint NOT NULL, event_hash text NOT NULL, event_type text NOT NULL,
 envelope jsonb NOT NULL, received_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(organization_id,event_id), UNIQUE(organization_id,source_database_id,sequence),
 FOREIGN KEY(organization_id,source_database_id) REFERENCES tapbix_online.writers(organization_id,database_id)
);
CREATE TABLE tapbix_online.deliveries (
 organization_id uuid NOT NULL, target_database_id uuid NOT NULL, event_id uuid NOT NULL,
 lease_token uuid, lease_until timestamptz, acknowledged_at timestamptz,
 PRIMARY KEY(organization_id,target_database_id,event_id),
 FOREIGN KEY(organization_id,target_database_id) REFERENCES tapbix_online.writers(organization_id,database_id),
 FOREIGN KEY(organization_id,event_id) REFERENCES tapbix_online.events(organization_id,event_id)
);
CREATE INDEX pending_deliveries ON tapbix_online.deliveries(organization_id,target_database_id)
 WHERE acknowledged_at IS NULL;
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['organizations','writers','credentials','invitations','events','deliveries'] LOOP
  EXECUTE format('ALTER TABLE tapbix_online.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('ALTER TABLE tapbix_online.%I FORCE ROW LEVEL SECURITY',t);
  EXECUTE format('CREATE POLICY tenant_isolation ON tapbix_online.%I USING (%I = nullif(current_setting(''tapbix.organization_id'',true),'''')::uuid) WITH CHECK (%I = nullif(current_setting(''tapbix.organization_id'',true),'''')::uuid)',t,CASE WHEN t='organizations' THEN 'id' ELSE 'organization_id' END,CASE WHEN t='organizations' THEN 'id' ELSE 'organization_id' END);
 END LOOP;
END $$;
GRANT USAGE ON SCHEMA tapbix_online TO tapbix_online_app;
GRANT SELECT ON ALL TABLES IN SCHEMA tapbix_online TO tapbix_online_app;
GRANT INSERT,UPDATE ON tapbix_online.writers,tapbix_online.credentials,tapbix_online.invitations,tapbix_online.deliveries TO tapbix_online_app;
GRANT INSERT ON tapbix_online.events TO tapbix_online_app;
-- Event history is immutable to the application role; no UPDATE/DELETE grant.
