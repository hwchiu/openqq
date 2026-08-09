package main

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/prometheus/client_golang/prometheus"
)

func testServer(upstream string, maxBody int64) *Server {
	return &Server{
		cfg:              Config{Upstream: upstream, UpstreamKey: "upstream-secret", MaxBody: maxBody},
		http:             &http.Client{},
		active:           *prometheus.NewGaugeVec(prometheus.GaugeOpts{Name: "test_active"}, []string{"tenant"}),
		requests:         prometheus.NewCounterVec(prometheus.CounterOpts{Name: "test_requests_total"}, []string{"tenant", "method", "route", "status"}),
		latency:          prometheus.NewHistogramVec(prometheus.HistogramOpts{Name: "test_latency"}, []string{"tenant", "method", "route"}),
		created:          prometheus.NewCounterVec(prometheus.CounterOpts{Name: "test_created_total"}, []string{"tenant"}),
		deleted:          prometheus.NewCounterVec(prometheus.CounterOpts{Name: "test_deleted_total"}, []string{"tenant"}),
		commands:         prometheus.NewCounterVec(prometheus.CounterOpts{Name: "test_commands_total"}, []string{"tenant"}),
		uploaded:         prometheus.NewCounterVec(prometheus.CounterOpts{Name: "test_uploaded_total"}, []string{"tenant"}),
		downloaded:       prometheus.NewCounterVec(prometheus.CounterOpts{Name: "test_downloaded_total"}, []string{"tenant"}),
		quota:            prometheus.NewCounterVec(prometheus.CounterOpts{Name: "test_quota_total"}, []string{"tenant"}),
		egressOperations: prometheus.NewCounterVec(prometheus.CounterOpts{Name: "test_egress_operations_total"}, []string{"tenant", "method", "result"}),
	}
}

func TestBearer(t *testing.T) {
	for name, header := range map[string]string{"valid": "Bearer abc", "trimmed": "Bearer   abc  "} {
		t.Run(name, func(t *testing.T) {
			r := httptest.NewRequest(http.MethodGet, "/", nil)
			r.Header.Set("Authorization", header)
			got, err := bearer(r)
			if err != nil || got != "abc" {
				t.Fatalf("bearer() = %q, %v", got, err)
			}
		})
	}
	for _, header := range []string{"", "Basic abc", "Bearer"} {
		r := httptest.NewRequest(http.MethodGet, "/", nil)
		r.Header.Set("Authorization", header)
		if _, err := bearer(r); err == nil {
			t.Fatalf("bearer(%q) unexpectedly succeeded", header)
		}
	}
}

func TestIdentityKey(t *testing.T) {
	got := identityKey(Identity{ClusterName: "local-cluster", Namespace: "team-a", ServiceAccount: "runner"})
	if got != "local-cluster/team-a/runner" {
		t.Fatalf("identityKey() = %q", got)
	}
	if got := identityUIDKey(Identity{ClusterName: "local-cluster", PrincipalUID: "sa-uid"}); got != "local-cluster/sa-uid" {
		t.Fatalf("identityUIDKey() = %q", got)
	}
}

func TestVerifyWithKFA(t *testing.T) {
	tokenFile, err := os.CreateTemp(t.TempDir(), "sa-token")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := tokenFile.WriteString("tenant-server-sa-token"); err != nil {
		t.Fatal(err)
	}
	_ = tokenFile.Close()
	kfa := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost || r.URL.Path != "/apis/authentication.k8s.io/v1/tokenreviews" {
			t.Fatalf("unexpected KFA request: %s %s", r.Method, r.URL.Path)
		}
		if got := r.Header.Get("Authorization"); got != "Bearer tenant-server-sa-token" {
			t.Fatalf("KFA caller credential = %q", got)
		}
		json.NewEncoder(w).Encode(map[string]any{"status": map[string]any{
			"authenticated": true,
			"user": map[string]any{
				"username": "system:serviceaccount:kfa-test:kfa-test-client",
				"uid":      "serviceaccount-uid-1",
				"extra":    map[string][]string{"authentication.kubernetes.io/cluster-name": {"local-cluster"}},
			},
		}})
	}))
	defer kfa.Close()
	s := testServer("http://unused", 1024)
	s.cfg.KFAURL = kfa.URL
	s.cfg.KFATokenPath = tokenFile.Name()
	s.http = kfa.Client()
	identity, err := s.verifyWithKFA(context.Background(), "client-token")
	if err != nil {
		t.Fatal(err)
	}
	if identity != (Identity{ClusterName: "local-cluster", Namespace: "kfa-test", ServiceAccount: "kfa-test-client", PrincipalUID: "serviceaccount-uid-1"}) {
		t.Fatalf("identity = %+v", identity)
	}
}

func TestVerifyWithKFATimeout(t *testing.T) {
	tokenFile, err := os.CreateTemp(t.TempDir(), "sa-token")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := tokenFile.WriteString("tenant-server-sa-token"); err != nil {
		t.Fatal(err)
	}
	_ = tokenFile.Close()
	kfa := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		time.Sleep(100 * time.Millisecond)
	}))
	defer kfa.Close()
	s := testServer("http://unused", 1024)
	s.cfg.KFAURL = kfa.URL
	s.cfg.KFATokenPath = tokenFile.Name()
	s.cfg.KFATimeout = 10 * time.Millisecond
	_, err = s.verifyWithKFA(context.Background(), "client-token")
	if err == nil || !strings.Contains(err.Error(), "context deadline exceeded") {
		t.Fatalf("verifyWithKFA error = %v, want timeout", err)
	}
}

func TestScope(t *testing.T) {
	s := testServer("http://unused", 1024)
	tenant := &Tenant{ID: "team-a", Scopes: "sandbox:read,sandbox:files"}
	if !tenant.scope(httptest.NewRecorder(), "sandbox:read") {
		t.Fatal("expected allowed scope")
	}
	w := httptest.NewRecorder()
	if tenant.scope(w, "sandbox:command") || w.Code != http.StatusForbidden {
		t.Fatalf("missing scope response = %d", w.Code)
	}
	_ = s
}

func TestValidateFQDN(t *testing.T) {
	for _, value := range []string{"example.com", "*.example.com"} {
		if got, err := validateFQDN(value); err != nil || got == "" {
			t.Fatalf("validateFQDN(%q) = %q, %v", value, got, err)
		}
	}
	for _, value := range []string{"https://example.com", "127.0.0.1", "10.0.0.0/8", "bad value"} {
		if _, err := validateFQDN(value); err == nil {
			t.Fatalf("validateFQDN(%q) unexpectedly succeeded", value)
		}
	}
}

func TestEgressPatchUsesPrivateEndpointAndAllowlist(t *testing.T) {
	egress := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("OPENSANDBOX-EGRESS-AUTH") != "egress-secret" {
			t.Fatalf("egress token missing")
		}
		if r.Method != http.MethodPatch || r.URL.Path != "/policy" {
			t.Fatalf("egress request = %s %s", r.Method, r.URL.Path)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, `{"ok":true}`)
	}))
	defer egress.Close()
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/sandboxes/sb-1/endpoints/18080" {
			t.Fatalf("endpoint lookup path = %s", r.URL.Path)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, `{"endpoint":"`+egress.URL+`"}`)
	}))
	defer upstream.Close()
	s := testServer(upstream.URL, 1024)
	s.cfg.EgressPort = 18080
	s.cfg.EgressToken = "egress-secret"
	s.cfg.EgressAllowedFQDNs = map[string]struct{}{"example.com": {}}
	s.cfg.EgressBaseline = []egressRule{{Action: "allow", Target: "opensandbox-server.opensandbox-system.svc.cluster.local"}}
	r := httptest.NewRequest(http.MethodPatch, "/v1/sandboxes/sb-1/egress", strings.NewReader(`{"action":"allow","target":"Example.com"}`))
	w := httptest.NewRecorder()
	s.egress(w, r, "sb-1", &Tenant{ID: "team-a", Scopes: "sandbox:egress"})
	if w.Code != http.StatusOK || w.Body.String() != `{"ok":true}` {
		t.Fatalf("egress response = %d %q", w.Code, w.Body.String())
	}
}

func TestForwardInjectsCredentialAndStreams(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if got := r.Header.Get("OPEN-SANDBOX-API-KEY"); got != "upstream-secret" {
			t.Errorf("upstream key = %q", got)
		}
		if got := r.Header.Get("Authorization"); got != "" {
			t.Errorf("authorization leaked upstream: %q", got)
		}
		if r.URL.Path != "/v1/sandboxes/sb-1/files/download" {
			t.Errorf("upstream path = %s", r.URL.Path)
		}
		w.WriteHeader(http.StatusCreated)
		_, _ = io.WriteString(w, "download-data")
	}))
	defer upstream.Close()
	s := testServer(upstream.URL, 1024)
	r := httptest.NewRequest(http.MethodGet, "/", strings.NewReader("request"))
	r.Header.Set("Authorization", "Bearer tenant-secret")
	w := httptest.NewRecorder()
	s.forward(w, r, "/v1/sandboxes/sb-1/files/download", &Tenant{ID: "team-a", Scopes: "sandbox:files"}, "sandbox:files")
	if w.Code != http.StatusCreated || w.Body.String() != "download-data" {
		t.Fatalf("forward response = %d %q", w.Code, w.Body.String())
	}
}

func TestForwardRejectsSnapshotAndOversizedBody(t *testing.T) {
	s := testServer("http://127.0.0.1:1", 4)
	tenant := &Tenant{ID: "team-a", Scopes: "sandbox:read"}
	w := httptest.NewRecorder()
	s.forward(w, httptest.NewRequest(http.MethodGet, "/", nil), "/v1/snapshots", tenant, "sandbox:read")
	if w.Code != http.StatusNotFound {
		t.Fatalf("snapshot status = %d", w.Code)
	}
	w = httptest.NewRecorder()
	r := httptest.NewRequest(http.MethodPost, "/", strings.NewReader("12345"))
	r.ContentLength = 5
	s.forward(w, r, "/v1/sandboxes", tenant, "sandbox:read")
	if w.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("oversized status = %d", w.Code)
	}
}

func TestHandlerHealthAndUnknownRoute(t *testing.T) {
	s := testServer("http://unused", 1024)
	for path, want := range map[string]int{"/health": http.StatusOK, "/unknown": http.StatusNotFound} {
		w := httptest.NewRecorder()
		s.handler(w, httptest.NewRequest(http.MethodGet, path, nil))
		if w.Code != want {
			t.Errorf("%s status = %d, want %d", path, w.Code, want)
		}
	}
}
