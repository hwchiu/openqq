package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

type Config struct {
	Upstream, UpstreamKey, DatabaseURL, EgressResetTemplate string
	KFAURL, KFATokenPath                                    string
	AdminIdentities                                         []string
	MaxBody                                                 int64
}
type Tenant struct {
	ID, ClusterName, Namespace, ServiceAccount, PrincipalUID, Scopes string
	MaxConcurrent                                                    int
	Enabled                                                          bool
}
type Identity struct {
	ClusterName, Namespace, ServiceAccount, PrincipalUID string
}
type TenantInput struct {
	TenantID       string   `json:"tenant_id"`
	ClusterName    string   `json:"cluster_name"`
	Namespace      string   `json:"namespace"`
	ServiceAccount string   `json:"service_account"`
	PrincipalUID   string   `json:"principal_uid"`
	Scopes         []string `json:"scopes"`
	MaxConcurrent  int      `json:"max_concurrent_sandboxes"`
}
type Server struct {
	cfg                                                     Config
	db                                                      *pgxpool.Pool
	http                                                    *http.Client
	active                                                  prometheus.GaugeVec
	requests                                                *prometheus.CounterVec
	latency                                                 *prometheus.HistogramVec
	created, deleted, commands, uploaded, downloaded, quota *prometheus.CounterVec
	metricsMu                                               sync.Mutex
}

type statusWriter struct {
	http.ResponseWriter
	status int
}

func (w *statusWriter) WriteHeader(code int) {
	if w.status == 0 {
		w.status = code
	}
	w.ResponseWriter.WriteHeader(code)
}
func (w *statusWriter) Write(p []byte) (int, error) {
	if w.status == 0 {
		w.status = http.StatusOK
	}
	return w.ResponseWriter.Write(p)
}

var (
	registry = prometheus.NewRegistry()
)

type tenantContextKey struct{}

func env(k, d string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return d
}
func identityKey(i Identity) string {
	return i.ClusterName + "/" + i.Namespace + "/" + i.ServiceAccount
}
func identityUIDKey(i Identity) string {
	if i.PrincipalUID == "" {
		return ""
	}
	return i.ClusterName + "/" + i.PrincipalUID
}
func bearer(r *http.Request) (string, error) {
	v := r.Header.Get("Authorization")
	if !strings.HasPrefix(v, "Bearer ") {
		return "", errors.New("Kubernetes ServiceAccount bearer token required")
	}
	return strings.TrimSpace(strings.TrimPrefix(v, "Bearer ")), nil
}
func jsonWrite(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}
func (s *Server) tenant(ctx context.Context, identity Identity) (*Tenant, error) {
	var t Tenant
	err := s.db.QueryRow(ctx, `SELECT tenant_id,cluster_name,namespace,service_account,principal_uid,scopes,max_concurrent,enabled FROM tenants WHERE cluster_name=$1 AND namespace=$2 AND service_account=$3 AND (principal_uid=$4 OR principal_uid='') AND enabled`, identity.ClusterName, identity.Namespace, identity.ServiceAccount, identity.PrincipalUID).Scan(&t.ID, &t.ClusterName, &t.Namespace, &t.ServiceAccount, &t.PrincipalUID, &t.Scopes, &t.MaxConcurrent, &t.Enabled)
	if err != nil {
		return nil, err
	}
	// Existing username-only mappings are upgraded on first successful KFA
	// authentication. New mappings should provide principal_uid explicitly.
	if identity.PrincipalUID != "" && t.PrincipalUID == "" {
		if _, err := s.db.Exec(ctx, `UPDATE tenants SET principal_uid=$1,updated_at=CURRENT_TIMESTAMP WHERE tenant_id=$2 AND principal_uid=''`, identity.PrincipalUID, t.ID); err != nil {
			return nil, err
		}
		t.PrincipalUID = identity.PrincipalUID
	}
	return &t, nil
}
func (t *Tenant) scope(w http.ResponseWriter, wanted string) bool {
	for _, v := range strings.Split(t.Scopes, ",") {
		if v == wanted {
			return true
		}
	}
	jsonWrite(w, 403, map[string]string{"detail": "missing scope: " + wanted})
	return false
}
func (s *Server) auth(w http.ResponseWriter, r *http.Request) *Tenant {
	identity, e := s.identity(w, r)
	if e != nil {
		return nil
	}
	t, e := s.tenant(r.Context(), identity)
	if e != nil {
		jsonWrite(w, 403, map[string]string{"detail": "ServiceAccount is not mapped to an enabled tenant"})
		return nil
	}
	*r = *r.WithContext(context.WithValue(r.Context(), tenantContextKey{}, t.ID))
	return t
}

func (s *Server) identity(w http.ResponseWriter, r *http.Request) (Identity, error) {
	token, err := bearer(r)
	if err != nil {
		jsonWrite(w, http.StatusUnauthorized, map[string]string{"detail": err.Error()})
		return Identity{}, err
	}
	identity, err := s.verifyWithKFA(r.Context(), token)
	if err != nil {
		jsonWrite(w, http.StatusUnauthorized, map[string]string{"detail": "invalid Kubernetes ServiceAccount identity"})
		return Identity{}, err
	}
	return identity, nil
}

type tokenReview struct {
	Status struct {
		Authenticated bool `json:"authenticated"`
		User          struct {
			Username string              `json:"username"`
			UID      string              `json:"uid"`
			Extra    map[string][]string `json:"extra"`
		} `json:"user"`
		Error string `json:"error"`
	} `json:"status"`
}

func (s *Server) verifyWithKFA(ctx context.Context, token string) (Identity, error) {
	serverToken, err := os.ReadFile(s.cfg.KFATokenPath)
	if err != nil {
		return Identity{}, fmt.Errorf("read KFA caller token: %w", err)
	}
	payload, err := json.Marshal(map[string]any{
		"apiVersion": "authentication.k8s.io/v1",
		"kind":       "TokenReview",
		"spec":       map[string]string{"token": token},
	})
	if err != nil {
		return Identity{}, fmt.Errorf("encode TokenReview: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, strings.TrimRight(s.cfg.KFAURL, "/")+"/apis/authentication.k8s.io/v1/tokenreviews", bytes.NewReader(payload))
	if err != nil {
		return Identity{}, fmt.Errorf("create KFA request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+strings.TrimSpace(string(serverToken)))
	req.Header.Set("Content-Type", "application/json")
	resp, err := s.http.Do(req)
	if err != nil {
		return Identity{}, fmt.Errorf("KFA unavailable: %w", err)
	}
	defer resp.Body.Close()
	var review tokenReview
	if err := json.NewDecoder(resp.Body).Decode(&review); err != nil {
		return Identity{}, fmt.Errorf("decode KFA response: %w", err)
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 || !review.Status.Authenticated {
		if review.Status.Error != "" {
			return Identity{}, errors.New(review.Status.Error)
		}
		return Identity{}, fmt.Errorf("KFA rejected token with HTTP %d", resp.StatusCode)
	}
	parts := strings.Split(review.Status.User.Username, ":")
	if len(parts) != 4 || parts[0] != "system" || parts[1] != "serviceaccount" || parts[2] == "" || parts[3] == "" {
		return Identity{}, fmt.Errorf("KFA returned unsupported username %q", review.Status.User.Username)
	}
	cluster := ""
	if values := review.Status.User.Extra["authentication.kubernetes.io/cluster-name"]; len(values) == 1 {
		cluster = values[0]
	}
	if cluster == "" {
		return Identity{}, errors.New("KFA response has no cluster identity")
	}
	if review.Status.User.UID == "" {
		return Identity{}, errors.New("KFA response has no ServiceAccount UID")
	}
	return Identity{ClusterName: cluster, Namespace: parts[2], ServiceAccount: parts[3], PrincipalUID: review.Status.User.UID}, nil
}
func (s *Server) admin(w http.ResponseWriter, r *http.Request) bool {
	identity, err := s.identity(w, r)
	if err != nil {
		return false
	}
	allowed := false
	for _, candidate := range s.cfg.AdminIdentities {
		candidate = strings.TrimSpace(candidate)
		if candidate == identityKey(identity) || candidate == identityUIDKey(identity) {
			allowed = true
			break
		}
	}
	if !allowed {
		jsonWrite(w, http.StatusForbidden, map[string]string{"detail": "ServiceAccount is not an admin identity"})
		return false
	}
	return true
}

func (s *Server) initDB(ctx context.Context) error {
	_, e := s.db.Exec(ctx, `CREATE TABLE IF NOT EXISTS tenants(tenant_id TEXT PRIMARY KEY,cluster_name TEXT NOT NULL DEFAULT '',namespace TEXT NOT NULL DEFAULT '',service_account TEXT NOT NULL DEFAULT '',principal_uid TEXT NOT NULL DEFAULT '',scopes TEXT NOT NULL,max_concurrent INTEGER NOT NULL,enabled BOOLEAN NOT NULL DEFAULT TRUE,created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP); ALTER TABLE tenants ADD COLUMN IF NOT EXISTS cluster_name TEXT NOT NULL DEFAULT ''; ALTER TABLE tenants ADD COLUMN IF NOT EXISTS namespace TEXT NOT NULL DEFAULT ''; ALTER TABLE tenants ADD COLUMN IF NOT EXISTS service_account TEXT NOT NULL DEFAULT ''; ALTER TABLE tenants ADD COLUMN IF NOT EXISTS principal_uid TEXT NOT NULL DEFAULT ''; ALTER TABLE tenants DROP COLUMN IF EXISTS key_hash; CREATE UNIQUE INDEX IF NOT EXISTS tenants_identity_idx ON tenants(cluster_name,namespace,service_account) WHERE cluster_name <> '' AND namespace <> '' AND service_account <> ''; CREATE UNIQUE INDEX IF NOT EXISTS tenants_principal_uid_idx ON tenants(cluster_name,principal_uid) WHERE cluster_name <> '' AND principal_uid <> ''; CREATE TABLE IF NOT EXISTS sandbox_owners(sandbox_id TEXT PRIMARY KEY,tenant_id TEXT NOT NULL,allocation_state TEXT NOT NULL DEFAULT 'allocated',created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,last_activity_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP); CREATE INDEX IF NOT EXISTS sandbox_owners_tenant_idx ON sandbox_owners(tenant_id,allocation_state);`)
	return e
}
func (s *Server) recordOwner(ctx context.Context, id, tenant string) error {
	_, e := s.db.Exec(ctx, `INSERT INTO sandbox_owners(sandbox_id,tenant_id) VALUES($1,$2) ON CONFLICT(sandbox_id) DO UPDATE SET tenant_id=EXCLUDED.tenant_id,allocation_state='allocated',last_activity_at=CURRENT_TIMESTAMP`, id, tenant)
	return e
}
func (s *Server) owns(ctx context.Context, id, tenant string) bool {
	var n int
	e := s.db.QueryRow(ctx, `SELECT 1 FROM sandbox_owners WHERE sandbox_id=$1 AND tenant_id=$2 AND allocation_state='allocated'`, id, tenant).Scan(&n)
	return e == nil
}
func (s *Server) activeCount(ctx context.Context, tenant string) int {
	var n int
	_ = s.db.QueryRow(ctx, `SELECT count(*) FROM sandbox_owners WHERE tenant_id=$1 AND allocation_state='allocated'`, tenant).Scan(&n)
	return n
}
func (s *Server) removeOwner(ctx context.Context, id, tenant string) {
	_, _ = s.db.Exec(ctx, `UPDATE sandbox_owners SET allocation_state='released',last_activity_at=CURRENT_TIMESTAMP WHERE sandbox_id=$1 AND tenant_id=$2 AND allocation_state='allocated'`, id, tenant)
	s.active.WithLabelValues(tenant).Dec()
}

func (s *Server) forward(w http.ResponseWriter, r *http.Request, path string, tenant *Tenant, required string) {
	if !tenant.scope(w, required) {
		return
	}
	if strings.Contains(path, "/snapshot") {
		jsonWrite(w, 404, map[string]string{"detail": "API route is not exposed by tenant server"})
		return
	}
	if r.ContentLength > s.cfg.MaxBody {
		jsonWrite(w, 413, map[string]string{"detail": "request body exceeds tenant server limit"})
		return
	}
	body := io.Reader(http.NoBody)
	if r.Body != nil {
		body = io.LimitReader(r.Body, s.cfg.MaxBody+1)
	}
	req, e := http.NewRequestWithContext(r.Context(), r.Method, s.cfg.Upstream+"/"+strings.TrimPrefix(path, "/"), body)
	if e != nil {
		jsonWrite(w, 500, map[string]string{"detail": e.Error()})
		return
	}
	for k, v := range r.Header {
		if strings.EqualFold(k, "Authorization") || strings.EqualFold(k, "OPEN-SANDBOX-API-KEY") || strings.EqualFold(k, "Content-Length") {
			continue
		}
		req.Header[k] = v
	}
	req.Header.Set("OPEN-SANDBOX-API-KEY", s.cfg.UpstreamKey)
	resp, e := s.http.Do(req)
	if e != nil {
		jsonWrite(w, 502, map[string]string{"detail": "upstream unavailable"})
		return
	}
	defer resp.Body.Close()
	for k, v := range resp.Header {
		if k == "Content-Length" {
			continue
		}
		w.Header()[k] = v
	}
	w.WriteHeader(resp.StatusCode)
	n, _ := io.CopyN(w, resp.Body, s.cfg.MaxBody+1)
	if n > s.cfg.MaxBody {
		return
	}
	if strings.Contains(path, "/files/download") {
		s.downloaded.WithLabelValues(tenant.ID).Add(float64(n))
	}
}

func (s *Server) create(w http.ResponseWriter, r *http.Request) {
	t := s.auth(w, r)
	if t == nil || !t.scope(w, "sandbox:create") {
		return
	}
	if s.activeCount(r.Context(), t.ID) >= t.MaxConcurrent {
		s.quota.WithLabelValues(t.ID).Inc()
		jsonWrite(w, 429, map[string]string{"detail": "tenant sandbox quota exceeded"})
		return
	}
	body, e := io.ReadAll(io.LimitReader(r.Body, s.cfg.MaxBody+1))
	if e != nil || int64(len(body)) > s.cfg.MaxBody {
		jsonWrite(w, 413, map[string]string{"detail": "request body exceeds tenant server limit"})
		return
	}
	req, _ := http.NewRequestWithContext(r.Context(), "POST", s.cfg.Upstream+"/v1/sandboxes", strings.NewReader(string(body)))
	req.Header.Set("Content-Type", r.Header.Get("Content-Type"))
	req.Header.Set("OPEN-SANDBOX-API-KEY", s.cfg.UpstreamKey)
	resp, e := s.http.Do(req)
	if e != nil {
		jsonWrite(w, 502, map[string]string{"detail": "upstream unavailable"})
		return
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode < 300 {
		var x struct {
			ID string `json:"id"`
		}
		if json.Unmarshal(data, &x) == nil && x.ID != "" {
			if e = s.recordOwner(r.Context(), x.ID, t.ID); e != nil {
				jsonWrite(w, 500, map[string]string{"detail": "ownership persistence failed"})
				return
			}
			s.created.WithLabelValues(t.ID).Inc()
			s.active.WithLabelValues(t.ID).Inc()
		}
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(resp.StatusCode)
	w.Write(data)
}
func (s *Server) list(w http.ResponseWriter, r *http.Request) {
	t := s.auth(w, r)
	if t == nil || !t.scope(w, "sandbox:read") {
		return
	}
	req, _ := http.NewRequestWithContext(r.Context(), "GET", s.cfg.Upstream+"/v1/sandboxes?"+r.URL.RawQuery, nil)
	req.Header.Set("OPEN-SANDBOX-API-KEY", s.cfg.UpstreamKey)
	resp, e := s.http.Do(req)
	if e != nil {
		jsonWrite(w, 502, map[string]string{"detail": "upstream unavailable"})
		return
	}
	defer resp.Body.Close()
	var p map[string]any
	if json.NewDecoder(resp.Body).Decode(&p) != nil {
		jsonWrite(w, 502, map[string]string{"detail": "invalid upstream response"})
		return
	}
	if items, ok := p["items"].([]any); ok {
		out := items[:0]
		for _, raw := range items {
			if x, ok := raw.(map[string]any); ok {
				if id, _ := x["id"].(string); s.owns(r.Context(), id, t.ID) {
					out = append(out, x)
				}
			}
		}
		p["items"] = out
	}
	jsonWrite(w, resp.StatusCode, p)
}
func (s *Server) sandbox(w http.ResponseWriter, r *http.Request) {
	rest := strings.TrimPrefix(r.URL.Path, "/v1/sandboxes/")
	parts := strings.SplitN(rest, "/", 2)
	id := parts[0]
	t := s.auth(w, r)
	if t == nil || !s.owns(r.Context(), id, t.ID) {
		if t != nil {
			jsonWrite(w, 404, map[string]string{"detail": "sandbox not found for tenant"})
		}
		return
	}
	if len(parts) == 1 {
		if r.Method == "DELETE" {
			s.forward(w, r, "/v1/sandboxes/"+id, t, "sandbox:delete")
			s.removeOwner(r.Context(), id, t.ID)
			s.deleted.WithLabelValues(t.ID).Inc()
			return
		}
		s.forward(w, r, "/v1/sandboxes/"+id, t, "sandbox:read")
		return
	}
	path := "/v1/sandboxes/" + rest
	required := "sandbox:command"
	if strings.Contains(path, "/files/") {
		required = "sandbox:files"
	}
	if strings.Contains(path, "/proxy/") {
		s.commands.WithLabelValues(t.ID).Inc()
	}
	s.forward(w, r, path, t, required)
}

func (s *Server) adminTenants(w http.ResponseWriter, r *http.Request) {
	if !s.admin(w, r) {
		return
	}
	if r.Method == "POST" {
		var in TenantInput
		if json.NewDecoder(r.Body).Decode(&in) != nil || in.TenantID == "" || in.ClusterName == "" || in.Namespace == "" || in.ServiceAccount == "" {
			jsonWrite(w, 400, map[string]string{"detail": "tenant_id, cluster_name, namespace and service_account are required"})
			return
		}
		if in.MaxConcurrent == 0 {
			in.MaxConcurrent = 3
		}
		if len(in.Scopes) == 0 {
			in.Scopes = []string{"sandbox:create", "sandbox:read", "sandbox:delete", "sandbox:command", "sandbox:files"}
		}
		_, e := s.db.Exec(r.Context(), `INSERT INTO tenants(tenant_id,cluster_name,namespace,service_account,principal_uid,scopes,max_concurrent) VALUES($1,$2,$3,$4,$5,$6,$7)`, in.TenantID, in.ClusterName, in.Namespace, in.ServiceAccount, in.PrincipalUID, strings.Join(in.Scopes, ","), in.MaxConcurrent)
		if e != nil {
			jsonWrite(w, 409, map[string]string{"detail": "tenant already exists"})
			return
		}
		jsonWrite(w, 200, map[string]any{"tenant_id": in.TenantID, "cluster_name": in.ClusterName, "namespace": in.Namespace, "service_account": in.ServiceAccount, "principal_uid": in.PrincipalUID, "scopes": in.Scopes, "max_concurrent_sandboxes": in.MaxConcurrent})
		return
	}
	rows, e := s.db.Query(r.Context(), `SELECT tenant_id,scopes,max_concurrent,enabled,created_at FROM tenants ORDER BY tenant_id`)
	if e != nil {
		jsonWrite(w, 500, map[string]string{"detail": "database unavailable"})
		return
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		var id, sc string
		var max int
		var enabled bool
		var created time.Time
		_ = rows.Scan(&id, &sc, &max, &enabled, &created)
		var cluster, namespace, serviceAccount, principalUID string
		_ = s.db.QueryRow(r.Context(), `SELECT cluster_name,namespace,service_account,principal_uid FROM tenants WHERE tenant_id=$1`, id).Scan(&cluster, &namespace, &serviceAccount, &principalUID)
		out = append(out, map[string]any{"tenant_id": id, "cluster_name": cluster, "namespace": namespace, "service_account": serviceAccount, "principal_uid": principalUID, "scopes": sc, "max_concurrent": max, "enabled": enabled, "created_at": created})
	}
	jsonWrite(w, 200, out)
}
func (s *Server) disable(w http.ResponseWriter, r *http.Request) {
	if !s.admin(w, r) {
		return
	}
	id := strings.TrimPrefix(r.URL.Path, "/admin/tenants/")
	tag, e := s.db.Exec(r.Context(), `UPDATE tenants SET enabled=FALSE,updated_at=CURRENT_TIMESTAMP WHERE tenant_id=$1`, id)
	if e != nil || tag.RowsAffected() == 0 {
		jsonWrite(w, 404, map[string]string{"detail": "tenant not found"})
		return
	}
	jsonWrite(w, 200, map[string]any{"tenant_id": id, "enabled": false})
}

func (s *Server) handler(w http.ResponseWriter, r *http.Request) {
	sw := &statusWriter{ResponseWriter: w}
	w = sw
	start := time.Now()
	tenant := "unauthenticated"
	route := r.URL.Path
	if strings.Contains(route, "/proxy/") {
		route = "/v1/sandboxes/{sandbox_id}/proxy/{port}/{operation}"
	}
	defer func() {
		if value, ok := r.Context().Value(tenantContextKey{}).(string); ok {
			tenant = value
		}
		status := sw.status
		if status == 0 {
			status = http.StatusOK
		}
		s.requests.WithLabelValues(tenant, r.Method, route, strconv.Itoa(status)).Inc()
		s.latency.WithLabelValues(tenant, r.Method, route).Observe(time.Since(start).Seconds())
	}()
	if r.URL.Path == "/health" {
		jsonWrite(w, 200, map[string]string{"status": "ok", "store": "postgres", "runtime": "go"})
		return
	}
	if r.URL.Path == "/metrics" {
		promhttp.HandlerFor(registry, promhttp.HandlerOpts{}).ServeHTTP(w, r)
		return
	}
	if strings.HasPrefix(r.URL.Path, "/admin/tenants") {
		if r.Method == "DELETE" {
			s.disable(w, r)
		} else {
			s.adminTenants(w, r)
		}
		return
	}
	if r.URL.Path == "/v1/sandboxes" && r.Method == "POST" {
		s.create(w, r)
		return
	}
	if r.URL.Path == "/v1/sandboxes" && r.Method == "GET" {
		s.list(w, r)
		return
	}
	if strings.HasPrefix(r.URL.Path, "/v1/sandboxes/") {
		s.sandbox(w, r)
		return
	}
	jsonWrite(w, 404, map[string]string{"detail": "API route is not exposed by tenant server"})
}

func main() {
	ctx := context.Background()
	cfg := Config{Upstream: strings.TrimRight(env("OPENSANDBOX_SERVER_URL", "http://opensandbox-server.opensandbox-system:8080"), "/"), UpstreamKey: os.Getenv("OPENSANDBOX_API_KEY"), DatabaseURL: os.Getenv("TENANT_SERVER_DATABASE_URL"), EgressResetTemplate: os.Getenv("EGRESS_RESET_URL_TEMPLATE"), KFAURL: strings.TrimRight(env("KFA_URL", "http://kube-federated-auth.kube-federated-auth.svc.cluster.local:8080"), "/"), KFATokenPath: env("KFA_TOKEN_PATH", "/var/run/secrets/kubernetes.io/serviceaccount/token"), AdminIdentities: strings.Split(env("TENANT_SERVER_ADMIN_IDENTITIES", "local-cluster/opensandbox-tenant-server/opensandbox-tenant-server"), ","), MaxBody: 50 * 1024 * 1024}
	if v, err := strconv.ParseInt(env("MAX_BODY_BYTES", strconv.FormatInt(cfg.MaxBody, 10)), 10, 64); err == nil {
		cfg.MaxBody = v
	}
	if cfg.DatabaseURL == "" {
		log.Fatal("TENANT_SERVER_DATABASE_URL is required")
	}
	pool, e := pgxpool.New(ctx, cfg.DatabaseURL)
	if e != nil {
		log.Fatal(e)
	}
	defer pool.Close()
	s := &Server{cfg: cfg, db: pool, http: &http.Client{Timeout: 0}, active: *prometheus.NewGaugeVec(prometheus.GaugeOpts{Name: "opensandbox_tenant_server_active_sandboxes", Help: "Active sandboxes owned by tenant"}, []string{"tenant"}), requests: prometheus.NewCounterVec(prometheus.CounterOpts{Name: "opensandbox_tenant_server_requests_total", Help: "Tenant Server requests"}, []string{"tenant", "method", "route", "status"}), latency: prometheus.NewHistogramVec(prometheus.HistogramOpts{Name: "opensandbox_tenant_server_request_duration_seconds", Help: "Tenant Server request latency"}, []string{"tenant", "method", "route"}), created: prometheus.NewCounterVec(prometheus.CounterOpts{Name: "opensandbox_tenant_server_sandboxes_created_total", Help: "Sandboxes created"}, []string{"tenant"}), deleted: prometheus.NewCounterVec(prometheus.CounterOpts{Name: "opensandbox_tenant_server_sandboxes_deleted_total", Help: "Sandboxes deleted"}, []string{"tenant"}), commands: prometheus.NewCounterVec(prometheus.CounterOpts{Name: "opensandbox_tenant_server_commands_total", Help: "Command requests"}, []string{"tenant"}), uploaded: prometheus.NewCounterVec(prometheus.CounterOpts{Name: "opensandbox_tenant_server_uploaded_bytes_total", Help: "Uploaded bytes"}, []string{"tenant"}), downloaded: prometheus.NewCounterVec(prometheus.CounterOpts{Name: "opensandbox_tenant_server_downloaded_bytes_total", Help: "Downloaded bytes"}, []string{"tenant"}), quota: prometheus.NewCounterVec(prometheus.CounterOpts{Name: "opensandbox_tenant_server_quota_rejections_total", Help: "Quota rejections"}, []string{"tenant"})}
	for _, c := range []prometheus.Collector{&s.active, s.requests, s.latency, s.created, s.deleted, s.commands, s.uploaded, s.downloaded, s.quota} {
		registry.MustRegister(c)
	}
	if e = s.initDB(ctx); e != nil {
		log.Fatal(e)
	}
	listenAddr := env("LISTEN_ADDR", ":8080")
	log.Printf("Go Tenant Server listening on %s with PostgreSQL", listenAddr)
	log.Fatal(http.ListenAndServe(listenAddr, http.HandlerFunc(s.handler)))
}
