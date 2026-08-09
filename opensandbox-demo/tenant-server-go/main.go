package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"net/url"
	"os"
	"regexp"
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
	KFATimeout                                              time.Duration
	EgressPort                                              int
	EgressToken                                             string
	EgressAllowedFQDNs                                      map[string]struct{}
	EgressBaseline                                          []egressRule
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
type egressRule struct {
	Action string `json:"action"`
	Target string `json:"target"`
}
type egressPolicy struct {
	DefaultAction string       `json:"defaultAction"`
	Egress        []egressRule `json:"egress"`
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
	errQuota = errors.New("tenant sandbox quota exceeded")
)

type tenantContextKey struct{}

func env(k, d string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return d
}

var fqdnPattern = regexp.MustCompile(`^(\*\.)?[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?$`)

func csvSet(value string) map[string]struct{} {
	out := map[string]struct{}{}
	for _, item := range strings.Split(value, ",") {
		item = strings.ToLower(strings.TrimSpace(item))
		if item != "" {
			out[item] = struct{}{}
		}
	}
	return out
}

func validateFQDN(value string) (string, error) {
	value = strings.ToLower(strings.TrimSpace(value))
	if value == "" || len(value) > 253 || strings.ContainsAny(value, "/\\ \t\r\n") || strings.Contains(value, "://") || !fqdnPattern.MatchString(value) {
		return "", errors.New("target must be a valid FQDN")
	}
	if net.ParseIP(strings.TrimPrefix(value, "*.")) != nil {
		return "", errors.New("IP addresses are not accepted as FQDN targets")
	}
	return value, nil
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
	err := s.db.QueryRow(ctx, `SELECT tenant_id,cluster_name,namespace,service_account,principal_uid,scopes,max_concurrent,enabled FROM tenants WHERE enabled AND (tenant_id IN (SELECT tenant_id FROM tenant_principals WHERE cluster_name=$1 AND principal_uid=$4 AND enabled) OR (cluster_name=$1 AND namespace=$2 AND service_account=$3 AND (principal_uid=$4 OR principal_uid='')))`, identity.ClusterName, identity.Namespace, identity.ServiceAccount, identity.PrincipalUID).Scan(&t.ID, &t.ClusterName, &t.Namespace, &t.ServiceAccount, &t.PrincipalUID, &t.Scopes, &t.MaxConcurrent, &t.Enabled)
	if err != nil {
		return nil, err
	}
	// Existing username-only mappings are upgraded on first successful KFA
	// authentication. New mappings should provide principal_uid explicitly.
	if identity.PrincipalUID != "" && t.PrincipalUID == "" {
		if err := s.bindPrincipal(ctx, t.ID, identity); err != nil {
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
	timeout := s.cfg.KFATimeout
	if timeout <= 0 {
		timeout = 10 * time.Second
	}
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
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
	return runMigrations(ctx, s.db)
}

func requestID(r *http.Request) string {
	if v := strings.TrimSpace(r.Header.Get("X-Request-ID")); v != "" && len(v) <= 128 && !strings.ContainsAny(v, "\r\n") {
		return v
	}
	id, err := reservationID()
	if err != nil {
		return fmt.Sprintf("request-%d", time.Now().UnixNano())
	}
	return id
}

func (s *Server) audit(ctx context.Context, id, tenantID, principalUID, action, resourceID, result, reason string) {
	if _, err := s.db.Exec(ctx, `INSERT INTO audit_events(request_id,tenant_id,principal_uid,action,resource_id,result,reason) VALUES($1,$2,$3,$4,$5,$6,$7)`, id, tenantID, principalUID, action, resourceID, result, reason); err != nil {
		log.Printf("audit write failed request=%s action=%s: %v", id, action, err)
	}
}

func reservationID() (string, error) {
	b := make([]byte, 12)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return "reservation-" + hex.EncodeToString(b), nil
}

func (s *Server) reserveQuota(ctx context.Context, tenantID string) (string, error) {
	id, err := reservationID()
	if err != nil {
		return "", err
	}
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return "", err
	}
	defer tx.Rollback(ctx)
	_, err = tx.Exec(ctx, `DELETE FROM quota_reservations WHERE created_at < CURRENT_TIMESTAMP - INTERVAL '10 minutes'`)
	if err != nil {
		return "", err
	}
	var limit int
	if err = tx.QueryRow(ctx, `SELECT max_concurrent FROM tenants WHERE tenant_id=$1 AND enabled FOR UPDATE`, tenantID).Scan(&limit); err != nil {
		return "", err
	}
	var used int
	if err = tx.QueryRow(ctx, `SELECT (SELECT count(*) FROM sandbox_owners WHERE tenant_id=$1 AND allocation_state='allocated') + (SELECT count(*) FROM quota_reservations WHERE tenant_id=$1)`, tenantID).Scan(&used); err != nil {
		return "", err
	}
	if used >= limit {
		return "", errQuota
	}
	if _, err = tx.Exec(ctx, `INSERT INTO quota_reservations(reservation_id,tenant_id) VALUES($1,$2)`, id, tenantID); err != nil {
		return "", err
	}
	if err = tx.Commit(ctx); err != nil {
		return "", err
	}
	return id, nil
}

func (s *Server) releaseQuota(ctx context.Context, id string) {
	_, _ = s.db.Exec(ctx, `DELETE FROM quota_reservations WHERE reservation_id=$1`, id)
}

func (s *Server) bindPrincipal(ctx context.Context, tenantID string, identity Identity) error {
	if identity.PrincipalUID == "" {
		return errors.New("ServiceAccount UID is required")
	}
	result, err := s.db.Exec(ctx, `INSERT INTO tenant_principals(tenant_id,cluster_name,principal_uid,namespace,service_account) VALUES($1,$2,$3,$4,$5) ON CONFLICT (cluster_name,principal_uid) DO UPDATE SET enabled=tenant_principals.enabled WHERE tenant_principals.tenant_id=$1`, tenantID, identity.ClusterName, identity.PrincipalUID, identity.Namespace, identity.ServiceAccount)
	if err != nil {
		return err
	}
	if result.RowsAffected() == 0 {
		return errors.New("ServiceAccount principal is already bound to another tenant")
	}
	_, err = s.db.Exec(ctx, `UPDATE tenants SET principal_uid=CASE WHEN principal_uid='' THEN $1 ELSE principal_uid END,updated_at=CURRENT_TIMESTAMP WHERE tenant_id=$2`, identity.PrincipalUID, tenantID)
	return err
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
	reservation, err := s.reserveQuota(r.Context(), t.ID)
	if errors.Is(err, errQuota) {
		s.quota.WithLabelValues(t.ID).Inc()
		s.audit(r.Context(), requestID(r), t.ID, t.PrincipalUID, "sandbox.create", "", "rejected", "quota exceeded")
		jsonWrite(w, 429, map[string]string{"detail": "tenant sandbox quota exceeded"})
		return
	}
	if err != nil {
		s.audit(r.Context(), requestID(r), t.ID, t.PrincipalUID, "sandbox.create", "", "failed", "quota state unavailable")
		jsonWrite(w, 503, map[string]string{"detail": "tenant quota state unavailable"})
		return
	}
	defer s.releaseQuota(r.Context(), reservation)
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
			s.audit(r.Context(), requestID(r), t.ID, t.PrincipalUID, "sandbox.create", x.ID, "succeeded", "")
		}
	}
	if resp.StatusCode >= 300 {
		s.audit(r.Context(), requestID(r), t.ID, t.PrincipalUID, "sandbox.create", "", "failed", fmt.Sprintf("upstream status %d", resp.StatusCode))
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

type egressEndpoint struct {
	Endpoint string            `json:"endpoint"`
	Headers  map[string]string `json:"headers"`
}

func (s *Server) sandboxEgressEndpoint(ctx context.Context, sandboxID string) (egressEndpoint, error) {
	if s.cfg.EgressPort <= 0 {
		return egressEndpoint{}, errors.New("egress endpoint is not configured")
	}
	requestCtx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(requestCtx, http.MethodGet, fmt.Sprintf("%s/v1/sandboxes/%s/endpoints/%d?use_server_proxy=true", s.cfg.Upstream, url.PathEscape(sandboxID), s.cfg.EgressPort), nil)
	if err != nil {
		return egressEndpoint{}, err
	}
	req.Header.Set("OPEN-SANDBOX-API-KEY", s.cfg.UpstreamKey)
	resp, err := s.http.Do(req)
	if err != nil {
		return egressEndpoint{}, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return egressEndpoint{}, fmt.Errorf("endpoint lookup returned HTTP %d", resp.StatusCode)
	}
	var endpoint egressEndpoint
	if err := json.NewDecoder(resp.Body).Decode(&endpoint); err != nil {
		return egressEndpoint{}, err
	}
	parsed, err := url.Parse(endpoint.Endpoint)
	if err != nil || parsed.Host == "" || (parsed.Scheme != "http" && parsed.Scheme != "https") {
		return egressEndpoint{}, errors.New("OpenSandbox returned an invalid egress endpoint")
	}
	if endpoint.Headers == nil {
		endpoint.Headers = map[string]string{}
	}
	if s.cfg.EgressToken != "" {
		endpoint.Headers["OPENSANDBOX-EGRESS-AUTH"] = s.cfg.EgressToken
	}
	return endpoint, nil
}

func (s *Server) egressPolicyRequest(ctx context.Context, endpoint egressEndpoint, method string, body any) (json.RawMessage, error) {
	requestCtx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()
	encoded, err := json.Marshal(body)
	if err != nil {
		return nil, err
	}
	req, err := http.NewRequestWithContext(requestCtx, method, strings.TrimRight(endpoint.Endpoint, "/")+"/policy", strings.NewReader(string(encoded)))
	if err != nil {
		return nil, err
	}
	for key, value := range endpoint.Headers {
		req.Header.Set(key, value)
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := s.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(io.LimitReader(resp.Body, s.cfg.MaxBody+1))
	if err != nil {
		return nil, err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("egress policy returned HTTP %d: %s", resp.StatusCode, strings.TrimSpace(string(data)))
	}
	return data, nil
}

func (s *Server) egress(w http.ResponseWriter, r *http.Request, sandboxID string, tenant *Tenant) {
	if !tenant.scope(w, "sandbox:egress") {
		return
	}
	endpoint, err := s.sandboxEgressEndpoint(r.Context(), sandboxID)
	if err != nil {
		jsonWrite(w, 502, map[string]string{"detail": "egress endpoint unavailable"})
		return
	}
	var data json.RawMessage
	switch r.Method {
	case http.MethodGet:
		data, err = s.egressPolicyRequest(r.Context(), endpoint, http.MethodGet, map[string]any{})
	case http.MethodPatch:
		var input egressRule
		if json.NewDecoder(r.Body).Decode(&input) != nil || (input.Action != "allow" && input.Action != "deny") {
			jsonWrite(w, 400, map[string]string{"detail": "action must be allow or deny"})
			return
		}
		input.Target, err = validateFQDN(input.Target)
		if err != nil {
			jsonWrite(w, 400, map[string]string{"detail": err.Error()})
			return
		}
		if input.Action == "allow" {
			if _, ok := s.cfg.EgressAllowedFQDNs[input.Target]; !ok {
				jsonWrite(w, 403, map[string]string{"detail": "FQDN is not in the administrator allowlist"})
				return
			}
		}
		if input.Action == "deny" {
			for _, baseline := range s.cfg.EgressBaseline {
				if baseline.Action == "allow" && baseline.Target == input.Target {
					jsonWrite(w, 403, map[string]string{"detail": "baseline FQDN cannot be removed"})
					return
				}
			}
		}
		data, err = s.egressPolicyRequest(r.Context(), endpoint, http.MethodPatch, []egressRule{input})
	case http.MethodDelete:
		var input struct {
			Target string `json:"target"`
		}
		if json.NewDecoder(r.Body).Decode(&input) != nil {
			jsonWrite(w, 400, map[string]string{"detail": "target is required"})
			return
		}
		input.Target, err = validateFQDN(input.Target)
		if err != nil {
			jsonWrite(w, 400, map[string]string{"detail": err.Error()})
			return
		}
		if _, ok := s.cfg.EgressAllowedFQDNs[input.Target]; !ok {
			jsonWrite(w, 403, map[string]string{"detail": "FQDN is not in the administrator allowlist"})
			return
		}
		for _, baseline := range s.cfg.EgressBaseline {
			if baseline.Action == "allow" && baseline.Target == input.Target {
				jsonWrite(w, 403, map[string]string{"detail": "baseline FQDN cannot be removed"})
				return
			}
		}
		data, err = s.egressPolicyRequest(r.Context(), endpoint, http.MethodDelete, []string{input.Target})
	default:
		jsonWrite(w, 405, map[string]string{"detail": "method not allowed"})
		return
	}
	if err != nil {
		jsonWrite(w, 502, map[string]string{"detail": "egress policy operation failed"})
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(data)
}

func (s *Server) resetEgress(ctx context.Context, sandboxID string) error {
	if s.cfg.EgressToken == "" || len(s.cfg.EgressBaseline) == 0 {
		return nil
	}
	endpoint, err := s.sandboxEgressEndpoint(ctx, sandboxID)
	if err != nil {
		return err
	}
	_, err = s.egressPolicyRequest(ctx, endpoint, http.MethodPost, egressPolicy{DefaultAction: "deny", Egress: s.cfg.EgressBaseline})
	return err
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
			if err := s.resetEgress(r.Context(), id); err != nil {
				s.audit(r.Context(), requestID(r), t.ID, t.PrincipalUID, "sandbox.delete", id, "blocked", "egress reset failed")
				jsonWrite(w, 502, map[string]string{"detail": "sandbox egress reset failed"})
				return
			}
			s.forward(w, r, "/v1/sandboxes/"+id, t, "sandbox:delete")
			s.removeOwner(r.Context(), id, t.ID)
			s.deleted.WithLabelValues(t.ID).Inc()
			s.audit(r.Context(), requestID(r), t.ID, t.PrincipalUID, "sandbox.delete", id, "requested", "")
			return
		}
		s.forward(w, r, "/v1/sandboxes/"+id, t, "sandbox:read")
		return
	}
	path := "/v1/sandboxes/" + rest
	if strings.HasSuffix(path, "/egress") {
		s.egress(w, r, id, t)
		return
	}
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
			in.Scopes = []string{"sandbox:create", "sandbox:read", "sandbox:delete", "sandbox:command", "sandbox:files", "sandbox:egress"}
		}
		_, e := s.db.Exec(r.Context(), `INSERT INTO tenants(tenant_id,cluster_name,namespace,service_account,principal_uid,scopes,max_concurrent) VALUES($1,$2,$3,$4,$5,$6,$7)`, in.TenantID, in.ClusterName, in.Namespace, in.ServiceAccount, in.PrincipalUID, strings.Join(in.Scopes, ","), in.MaxConcurrent)
		if e != nil {
			jsonWrite(w, 409, map[string]string{"detail": "tenant already exists"})
			return
		}
		if in.PrincipalUID != "" {
			if e = s.bindPrincipal(r.Context(), in.TenantID, Identity{ClusterName: in.ClusterName, Namespace: in.Namespace, ServiceAccount: in.ServiceAccount, PrincipalUID: in.PrincipalUID}); e != nil {
				_, _ = s.db.Exec(r.Context(), `DELETE FROM tenants WHERE tenant_id=$1`, in.TenantID)
				jsonWrite(w, 409, map[string]string{"detail": "principal binding failed: " + e.Error()})
				return
			}
		}
		s.audit(r.Context(), requestID(r), in.TenantID, in.PrincipalUID, "tenant.create", in.TenantID, "succeeded", "")
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
	s.audit(r.Context(), requestID(r), id, "", "tenant.disable", id, "succeeded", "")
}

func (s *Server) adminPrincipal(w http.ResponseWriter, r *http.Request) {
	if !s.admin(w, r) {
		return
	}
	tenantID := strings.TrimSuffix(strings.TrimPrefix(r.URL.Path, "/admin/tenants/"), "/principals")
	var in TenantInput
	if json.NewDecoder(r.Body).Decode(&in) != nil || in.ClusterName == "" || in.Namespace == "" || in.ServiceAccount == "" || in.PrincipalUID == "" {
		jsonWrite(w, 400, map[string]string{"detail": "cluster_name, namespace, service_account and principal_uid are required"})
		return
	}
	var exists bool
	if err := s.db.QueryRow(r.Context(), `SELECT EXISTS(SELECT 1 FROM tenants WHERE tenant_id=$1)`, tenantID).Scan(&exists); err != nil || !exists {
		jsonWrite(w, 404, map[string]string{"detail": "tenant not found"})
		return
	}
	if err := s.bindPrincipal(r.Context(), tenantID, Identity{ClusterName: in.ClusterName, Namespace: in.Namespace, ServiceAccount: in.ServiceAccount, PrincipalUID: in.PrincipalUID}); err != nil {
		jsonWrite(w, 409, map[string]string{"detail": "principal binding failed: " + err.Error()})
		return
	}
	s.audit(r.Context(), requestID(r), tenantID, in.PrincipalUID, "principal.bind", in.PrincipalUID, "succeeded", "")
	jsonWrite(w, 200, map[string]any{"tenant_id": tenantID, "cluster_name": in.ClusterName, "namespace": in.Namespace, "service_account": in.ServiceAccount, "principal_uid": in.PrincipalUID, "enabled": true})
}

func (s *Server) handler(w http.ResponseWriter, r *http.Request) {
	sw := &statusWriter{ResponseWriter: w}
	w = sw
	rid := requestID(r)
	r.Header.Set("X-Request-ID", rid)
	w.Header().Set("X-Request-ID", rid)
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
	if strings.HasSuffix(r.URL.Path, "/principals") && strings.HasPrefix(r.URL.Path, "/admin/tenants/") && r.Method == "POST" {
		s.adminPrincipal(w, r)
		return
	}
	if r.URL.Path == "/admin/tenants" && (r.Method == "GET" || r.Method == "POST") {
		s.adminTenants(w, r)
		return
	}
	if strings.HasPrefix(r.URL.Path, "/admin/tenants/") && r.Method == "DELETE" {
		s.disable(w, r)
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
	kfaTimeout, _ := time.ParseDuration(env("KFA_TIMEOUT", "10s"))
	egressPort, _ := strconv.Atoi(env("OPENSANDBOX_EGRESS_PORT", "18080"))
	baselineTarget := env("OPENSANDBOX_EGRESS_BASELINE_FQDN", "opensandbox-server.opensandbox-system.svc.cluster.local")
	cfg := Config{Upstream: strings.TrimRight(env("OPENSANDBOX_SERVER_URL", "http://opensandbox-server.opensandbox-system:8080"), "/"), UpstreamKey: os.Getenv("OPENSANDBOX_API_KEY"), DatabaseURL: os.Getenv("TENANT_SERVER_DATABASE_URL"), EgressResetTemplate: os.Getenv("EGRESS_RESET_URL_TEMPLATE"), KFAURL: strings.TrimRight(env("KFA_URL", "http://kube-federated-auth.kube-federated-auth.svc.cluster.local:8080"), "/"), KFATokenPath: env("KFA_TOKEN_PATH", "/var/run/secrets/kubernetes.io/serviceaccount/token"), KFATimeout: kfaTimeout, EgressPort: egressPort, EgressToken: os.Getenv("OPENSANDBOX_EGRESS_TOKEN"), EgressAllowedFQDNs: csvSet(os.Getenv("OPENSANDBOX_EGRESS_ALLOWED_FQDNS")), EgressBaseline: []egressRule{{Action: "allow", Target: baselineTarget}}, AdminIdentities: strings.Split(env("TENANT_SERVER_ADMIN_IDENTITIES", "local-cluster/opensandbox-tenant-server/opensandbox-tenant-server"), ","), MaxBody: 50 * 1024 * 1024}
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
