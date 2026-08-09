package main

import (
	"context"
	"fmt"
	"os"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Run with TEST_DATABASE_URL against a disposable PostgreSQL database. The
// default unit test suite remains independent of external services.
func TestPostgresPrincipalAndQuotaIntegration(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL is not set")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	db, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	s := &Server{db: db}
	if err := s.initDB(ctx); err != nil {
		t.Fatal(err)
	}
	var migrationCount int
	if err := db.QueryRow(ctx, `SELECT count(*) FROM schema_migrations`).Scan(&migrationCount); err != nil {
		t.Fatal(err)
	}
	if migrationCount != len(schemaMigrations) {
		t.Fatalf("migration count=%d, want %d", migrationCount, len(schemaMigrations))
	}
	if err := s.initDB(ctx); err != nil {
		t.Fatal(err)
	}
	tenantID := fmt.Sprintf("integration-%d", time.Now().UnixNano())
	defer db.Exec(context.Background(), `DELETE FROM tenants WHERE tenant_id=$1`, tenantID)
	if _, err := db.Exec(ctx, `INSERT INTO tenants(tenant_id,cluster_name,namespace,service_account,scopes,max_concurrent) VALUES($1,'test-cluster','test-ns','legacy','sandbox:create',1)`, tenantID); err != nil {
		t.Fatal(err)
	}
	identity := Identity{ClusterName: "test-cluster", Namespace: "test-ns", ServiceAccount: "runner", PrincipalUID: "uid-integration"}
	if err := s.bindPrincipal(ctx, tenantID, identity); err != nil {
		t.Fatal(err)
	}
	got, err := s.tenant(ctx, identity)
	if err != nil || got.ID != tenantID || got.PrincipalUID != identity.PrincipalUID {
		t.Fatalf("tenant lookup = %+v, err=%v", got, err)
	}

	var wg sync.WaitGroup
	results := make(chan error, 8)
	reservations := make(chan string, 8)
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			reservation, err := s.reserveQuota(ctx, tenantID)
			if err == nil {
				reservations <- reservation
			}
			results <- err
		}()
	}
	wg.Wait()
	close(results)
	close(reservations)
	for reservation := range reservations {
		s.releaseQuota(ctx, reservation)
	}
	accepted, rejected := 0, 0
	for err := range results {
		if err == nil {
			accepted++
		} else if err == errQuota {
			rejected++
		} else {
			t.Fatalf("quota reservation error: %v", err)
		}
	}
	if accepted != 1 || rejected != 7 {
		t.Fatalf("quota reservations accepted=%d rejected=%d, want 1/7", accepted, rejected)
	}
}
