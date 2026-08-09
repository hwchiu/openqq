package main

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
)

type schemaMigration struct {
	Version int
	Name    string
	SQL     string
}

var schemaMigrations = []schemaMigration{
	{
		Version: 1,
		Name:    "tenant ownership baseline",
		SQL: `
CREATE TABLE IF NOT EXISTS tenants(
  tenant_id TEXT PRIMARY KEY,
  cluster_name TEXT NOT NULL DEFAULT '',
  namespace TEXT NOT NULL DEFAULT '',
  service_account TEXT NOT NULL DEFAULT '',
  scopes TEXT NOT NULL,
  max_concurrent INTEGER NOT NULL,
  enabled BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS tenants_identity_idx
  ON tenants(cluster_name,namespace,service_account)
  WHERE cluster_name <> '' AND namespace <> '' AND service_account <> '';
CREATE TABLE IF NOT EXISTS sandbox_owners(
  sandbox_id TEXT PRIMARY KEY,
  tenant_id TEXT NOT NULL,
  allocation_state TEXT NOT NULL DEFAULT 'allocated',
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_activity_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS sandbox_owners_tenant_idx
  ON sandbox_owners(tenant_id,allocation_state);
`,
	},
	{
		Version: 2,
		Name:    "KFA principal UID bindings",
		SQL: `
ALTER TABLE tenants ADD COLUMN IF NOT EXISTS cluster_name TEXT NOT NULL DEFAULT '';
ALTER TABLE tenants ADD COLUMN IF NOT EXISTS namespace TEXT NOT NULL DEFAULT '';
ALTER TABLE tenants ADD COLUMN IF NOT EXISTS service_account TEXT NOT NULL DEFAULT '';
ALTER TABLE tenants ADD COLUMN IF NOT EXISTS principal_uid TEXT NOT NULL DEFAULT '';
ALTER TABLE tenants DROP COLUMN IF EXISTS key_hash;
CREATE UNIQUE INDEX IF NOT EXISTS tenants_principal_uid_idx
  ON tenants(cluster_name,principal_uid)
  WHERE cluster_name <> '' AND principal_uid <> '';
CREATE TABLE IF NOT EXISTS tenant_principals(
  principal_id BIGSERIAL PRIMARY KEY,
  tenant_id TEXT NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
  cluster_name TEXT NOT NULL,
  principal_uid TEXT NOT NULL,
  namespace TEXT NOT NULL,
  service_account TEXT NOT NULL,
  enabled BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS tenant_principal_uid_idx
  ON tenant_principals(cluster_name,principal_uid);
CREATE UNIQUE INDEX IF NOT EXISTS tenant_principal_name_idx
  ON tenant_principals(cluster_name,namespace,service_account);
INSERT INTO tenant_principals(tenant_id,cluster_name,principal_uid,namespace,service_account)
SELECT tenant_id,cluster_name,principal_uid,namespace,service_account
FROM tenants
WHERE principal_uid <> ''
ON CONFLICT (cluster_name,principal_uid) DO NOTHING;
`,
	},
	{
		Version: 3,
		Name:    "quota reservations and audit events",
		SQL: `
CREATE TABLE IF NOT EXISTS quota_reservations(
  reservation_id TEXT PRIMARY KEY,
  tenant_id TEXT NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS quota_reservations_tenant_idx
  ON quota_reservations(tenant_id,created_at);
CREATE TABLE IF NOT EXISTS audit_events(
  event_id BIGSERIAL PRIMARY KEY,
  request_id TEXT NOT NULL,
  tenant_id TEXT NOT NULL DEFAULT '',
  principal_uid TEXT NOT NULL DEFAULT '',
  action TEXT NOT NULL,
  resource_id TEXT NOT NULL DEFAULT '',
  result TEXT NOT NULL,
  reason TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS audit_events_tenant_time_idx
  ON audit_events(tenant_id,created_at DESC);
`,
	},
}

func runMigrations(ctx context.Context, db *pgxpool.Pool) error {
	if _, err := db.Exec(ctx, `CREATE TABLE IF NOT EXISTS schema_migrations(version INTEGER PRIMARY KEY,name TEXT NOT NULL,applied_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP)`); err != nil {
		return err
	}
	for _, migration := range schemaMigrations {
		var applied bool
		if err := db.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM schema_migrations WHERE version=$1)`, migration.Version).Scan(&applied); err != nil {
			return err
		}
		if applied {
			continue
		}
		tx, err := db.Begin(ctx)
		if err != nil {
			return err
		}
		if _, err = tx.Exec(ctx, migration.SQL); err == nil {
			_, err = tx.Exec(ctx, `INSERT INTO schema_migrations(version,name) VALUES($1,$2)`, migration.Version, migration.Name)
		}
		if err != nil {
			_ = tx.Rollback(ctx)
			return err
		}
		if err = tx.Commit(ctx); err != nil {
			return err
		}
	}
	return nil
}
