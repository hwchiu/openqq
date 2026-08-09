from __future__ import annotations

import asyncio
import hashlib
import hmac
import json
import os
import secrets
import sqlite3
import time
from contextlib import closing
from pathlib import Path
from typing import Any, AsyncIterator

import httpx
from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.responses import JSONResponse, PlainTextResponse, StreamingResponse
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Gauge, Histogram, generate_latest
from pydantic import BaseModel, Field

try:
    import psycopg
except ImportError:  # SQLite / ConfigMap / Vault development modes do not need psycopg.
    psycopg = None


UPSTREAM = os.getenv("OPENSANDBOX_SERVER_URL", "http://opensandbox-server.opensandbox-system.svc.cluster.local:8080").rstrip("/")
UPSTREAM_KEY = os.getenv("OPENSANDBOX_API_KEY", "")
ADMIN_TOKEN = os.getenv("TENANT_SERVER_ADMIN_TOKEN", "")
STORE_KIND = os.getenv("TENANT_STORE", "sqlite").lower()
DATABASE_URL = os.getenv("TENANT_SERVER_DATABASE_URL", "")
STATE_STORE_KIND = os.getenv("TENANT_SERVER_STATE_STORE", STORE_KIND).lower()
DB_PATH = os.getenv("TENANT_SERVER_DB_PATH", "/data/tenant server.db")
CONFIG_PATH = os.getenv("TENANT_CONFIG_PATH", "/config/tenants.json")
VAULT_ADDR = os.getenv("VAULT_ADDR", "").rstrip("/")
VAULT_TOKEN = os.getenv("VAULT_TOKEN", "")
VAULT_ROLE = os.getenv("VAULT_ROLE", "opensandbox-tenant-server")
VAULT_KV_MOUNT = os.getenv("VAULT_KV_MOUNT", "secret")
VAULT_PREFIX = os.getenv("VAULT_PREFIX", "opensandbox/tenants")
VAULT_CACHE_SECONDS = float(os.getenv("VAULT_CACHE_SECONDS", "5"))
MAX_BODY_BYTES = int(os.getenv("MAX_BODY_BYTES", str(50 * 1024 * 1024)))
DENIED_PATHS = ("/snapshots", "/snapshot")

REQUESTS = Counter("opensandbox_tenant_server_requests_total", "Tenant Server requests", ["tenant", "method", "route", "status"])
REQUEST_LATENCY = Histogram("opensandbox_tenant_server_request_duration_seconds", "Tenant Server request latency", ["tenant", "method", "route"])
SANDBOX_CREATED = Counter("opensandbox_tenant_server_sandboxes_created_total", "Sandboxes created", ["tenant"])
SANDBOX_DELETED = Counter("opensandbox_tenant_server_sandboxes_deleted_total", "Sandboxes deleted", ["tenant"])
COMMANDS = Counter("opensandbox_tenant_server_commands_total", "Sandbox command requests", ["tenant"])
UPLOADED = Counter("opensandbox_tenant_server_uploaded_bytes_total", "Request bytes accepted", ["tenant"])
DOWNLOADED = Counter("opensandbox_tenant_server_downloaded_bytes_total", "Response bytes streamed", ["tenant"])
ACTIVE = Gauge("opensandbox_tenant_server_active_sandboxes", "Active sandboxes owned by tenant", ["tenant"])
QUOTA_REJECTED = Counter("opensandbox_tenant_server_quota_rejections_total", "Tenant quota rejections", ["tenant"])

app = FastAPI(title="OpenSandbox Tenant Tenant Server", version="0.2.0")


class TenantInput(BaseModel):
    tenant_id: str = Field(pattern=r"^[a-z0-9][a-z0-9-]{1,62}$")
    scopes: list[str] = ["sandbox:create", "sandbox:read", "sandbox:delete", "sandbox:command", "sandbox:files"]
    max_concurrent_sandboxes: int = Field(default=3, ge=1, le=100)


def sha(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()


def new_key() -> str:
    return "osb_tenant_" + secrets.token_urlsafe(32)


def validate_key(token: str | None) -> str:
    if not token or not token.startswith("Bearer "):
        raise HTTPException(401, "tenant bearer token required")
    return token.removeprefix("Bearer ").strip()


class TenantStore:
    async def get_by_key(self, raw_key: str) -> dict[str, Any] | None:
        raise NotImplementedError

    async def create(self, data: dict[str, Any]) -> str:
        raise NotImplementedError

    async def list(self) -> list[dict[str, Any]]:
        raise NotImplementedError

    async def disable(self, tenant_id: str) -> bool:
        raise NotImplementedError


class SQLiteTenantStore(TenantStore):
    def _init(self) -> sqlite3.Connection:
        conn = sqlite3.connect(DB_PATH, timeout=10)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("""CREATE TABLE IF NOT EXISTS tenants (
            tenant_id TEXT PRIMARY KEY, key_hash TEXT NOT NULL, scopes TEXT NOT NULL,
            max_concurrent INTEGER NOT NULL, enabled INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        )""")
        conn.commit()
        return conn

    async def get_by_key(self, raw_key: str) -> dict[str, Any] | None:
        def read():
            with closing(self._init()) as conn:
                row = conn.execute("SELECT * FROM tenants WHERE key_hash=? AND enabled=1", (sha(raw_key),)).fetchone()
                return dict(row) if row else None
        return await asyncio.to_thread(read)

    async def create(self, data: dict[str, Any]) -> str:
        raw = new_key()
        def write():
            with closing(self._init()) as conn:
                conn.execute("INSERT INTO tenants(tenant_id,key_hash,scopes,max_concurrent) VALUES(?,?,?,?)", (data["tenant_id"], sha(raw), ",".join(sorted(set(data["scopes"]))), data["max_concurrent_sandboxes"]))
                conn.commit()
        try:
            await asyncio.to_thread(write)
        except sqlite3.IntegrityError as exc:
            raise HTTPException(409, "tenant already exists") from exc
        return raw

    async def list(self) -> list[dict[str, Any]]:
        def read():
            with closing(self._init()) as conn:
                return [dict(r) for r in conn.execute("SELECT tenant_id,scopes,max_concurrent,enabled,created_at FROM tenants ORDER BY tenant_id")]
        return await asyncio.to_thread(read)

    async def disable(self, tenant_id: str) -> bool:
        def write():
            with closing(self._init()) as conn:
                n = conn.execute("UPDATE tenants SET enabled=0 WHERE tenant_id=?", (tenant_id,)).rowcount
                conn.commit(); return bool(n)
        return await asyncio.to_thread(write)


class PostgresTenantStore(TenantStore):
    """Shared tenant store for horizontally scaled tenant server replicas."""
    def _conn(self):
        if not psycopg or not DATABASE_URL:
            raise RuntimeError("psycopg and TENANT_SERVER_DATABASE_URL are required for postgres mode")
        return psycopg.connect(DATABASE_URL)

    def _init(self):
        with self._conn() as conn:
            conn.execute("""CREATE TABLE IF NOT EXISTS tenants (
                tenant_id TEXT PRIMARY KEY, key_hash TEXT NOT NULL UNIQUE, scopes TEXT NOT NULL,
                max_concurrent INTEGER NOT NULL, enabled BOOLEAN NOT NULL DEFAULT TRUE,
                created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
            )""")
            conn.commit()

    async def get_by_key(self, raw_key: str) -> dict[str, Any] | None:
        def read():
            self._init()
            with self._conn() as conn:
                row = conn.execute("SELECT * FROM tenants WHERE key_hash=%s AND enabled=TRUE", (sha(raw_key),)).fetchone()
                if not row: return None
                columns = [d.name for d in conn.execute("SELECT * FROM tenants LIMIT 0").description]
                item = dict(zip(columns, row)); item["scopes"] = item["scopes"].split(",")
                return item
        return await asyncio.to_thread(read)

    async def create(self, data: dict[str, Any]) -> str:
        raw = new_key()
        def write():
            self._init()
            with self._conn() as conn:
                conn.execute("INSERT INTO tenants(tenant_id,key_hash,scopes,max_concurrent) VALUES(%s,%s,%s,%s)", (data["tenant_id"], sha(raw), ",".join(sorted(set(data["scopes"]))), data["max_concurrent_sandboxes"]))
                conn.commit()
        try:
            await asyncio.to_thread(write)
        except Exception as exc:
            if "duplicate key" in str(exc).lower(): raise HTTPException(409, "tenant already exists") from exc
            raise
        return raw

    async def list(self) -> list[dict[str, Any]]:
        def read():
            self._init()
            with self._conn() as conn:
                rows = conn.execute("SELECT tenant_id,scopes,max_concurrent,enabled,created_at FROM tenants ORDER BY tenant_id").fetchall()
                return [{"tenant_id": r[0], "scopes": r[1], "max_concurrent": r[2], "enabled": r[3], "created_at": r[4]} for r in rows]
        return await asyncio.to_thread(read)

    async def disable(self, tenant_id: str) -> bool:
        def write():
            self._init()
            with self._conn() as conn:
                cur = conn.execute("UPDATE tenants SET enabled=FALSE,updated_at=CURRENT_TIMESTAMP WHERE tenant_id=%s", (tenant_id,)); conn.commit(); return cur.rowcount > 0
        return await asyncio.to_thread(write)


class ConfigMapTenantStore(TenantStore):
    """Read-only development store. File changes are picked up by mtime."""
    def __init__(self): self._mtime = 0.0; self._data: dict[str, Any] = {}

    def _load(self) -> dict[str, Any]:
        path = Path(CONFIG_PATH)
        if not path.exists(): return {}
        mtime = path.stat().st_mtime
        if mtime != self._mtime:
            self._data = json.loads(path.read_text()); self._mtime = mtime
        return self._data.get("tenants", self._data)

    async def get_by_key(self, raw_key: str) -> dict[str, Any] | None:
        for tenant_id, item in self._load().items():
            if item.get("enabled", True) and hmac.compare_digest(item.get("key_hash", ""), sha(raw_key)):
                return {"tenant_id": tenant_id, **item}
        return None

    async def create(self, data: dict[str, Any]) -> str:
        raise HTTPException(501, "configmap store is read-only; apply the ConfigMap to add tenants")

    async def list(self): return [{"tenant_id": k, **v} for k, v in self._load().items()]
    async def disable(self, tenant_id: str): raise HTTPException(501, "configmap store is read-only")


class VaultTenantStore(TenantStore):
    """Vault KV v2 store with a short cache; changes take effect without restart."""
    def __init__(self): self._token = VAULT_TOKEN; self._cache: tuple[float, dict[str, Any]] = (0, {})

    async def _auth(self) -> str:
        if self._token: return self._token
        jwt_path = "/var/run/secrets/kubernetes.io/serviceaccount/token"
        jwt = Path(jwt_path).read_text()
        async with httpx.AsyncClient(timeout=10) as client:
            r = await client.post(f"{VAULT_ADDR}/v1/auth/kubernetes/login", json={"role": VAULT_ROLE, "jwt": jwt})
            r.raise_for_status(); self._token = r.json()["auth"]["client_token"]
        return self._token

    async def _read_index(self) -> dict[str, Any]:
        now = asyncio.get_running_loop().time()
        if now - self._cache[0] < VAULT_CACHE_SECONDS: return self._cache[1]
        token = await self._auth()
        url = f"{VAULT_ADDR}/v1/{VAULT_KV_MOUNT}/data/{VAULT_PREFIX}/index"
        async with httpx.AsyncClient(timeout=10) as client:
            r = await client.get(url, headers={"X-Vault-Token": token})
            if r.status_code == 404: index = {}
            else: r.raise_for_status(); index = r.json()["data"]["data"]
        self._cache = (now, index); return index

    async def _write(self, path: str, data: dict[str, Any]) -> None:
        token = await self._auth()
        async with httpx.AsyncClient(timeout=10) as client:
            r = await client.post(f"{VAULT_ADDR}/v1/{VAULT_KV_MOUNT}/data/{path}", headers={"X-Vault-Token": token}, json={"data": data})
            r.raise_for_status()

    async def get_by_key(self, raw_key: str) -> dict[str, Any] | None:
        index = await self._read_index(); tenant_id = index.get(sha(raw_key))
        if not tenant_id: return None
        token = await self._auth()
        async with httpx.AsyncClient(timeout=10) as client:
            r = await client.get(f"{VAULT_ADDR}/v1/{VAULT_KV_MOUNT}/data/{VAULT_PREFIX}/{tenant_id}", headers={"X-Vault-Token": token})
            if r.status_code == 404: return None
            r.raise_for_status(); item = r.json()["data"]["data"]
        return {"tenant_id": tenant_id, **item} if item.get("enabled", True) else None

    async def create(self, data: dict[str, Any]) -> str:
        index = await self._read_index()
        if data["tenant_id"] in index.values(): raise HTTPException(409, "tenant already exists")
        raw = new_key(); item = {"key_hash": sha(raw), "scopes": data["scopes"], "max_concurrent_sandboxes": data["max_concurrent_sandboxes"], "enabled": True}
        await self._write(f"{VAULT_PREFIX}/{data['tenant_id']}", item)
        index[sha(raw)] = data["tenant_id"]; await self._write(f"{VAULT_PREFIX}/index", index); self._cache = (0, {})
        return raw

    async def list(self):
        index = await self._read_index(); return [{"tenant_id": v} for v in sorted(set(index.values()))]

    async def disable(self, tenant_id: str) -> bool:
        index = await self._read_index(); hashes = [k for k, v in index.items() if v == tenant_id]
        if not hashes: return False
        token = await self._auth()
        async with httpx.AsyncClient(timeout=10) as client:
            r = await client.get(f"{VAULT_ADDR}/v1/{VAULT_KV_MOUNT}/data/{VAULT_PREFIX}/{tenant_id}", headers={"X-Vault-Token": token}); r.raise_for_status(); item = r.json()["data"]["data"]
        item["enabled"] = False; await self._write(f"{VAULT_PREFIX}/{tenant_id}", item); self._cache = (0, {}); return True


def make_store() -> TenantStore:
    if STORE_KIND == "vault": return VaultTenantStore()
    if STORE_KIND == "configmap": return ConfigMapTenantStore()
    if STORE_KIND == "postgres": return PostgresTenantStore()
    return SQLiteTenantStore()


store = make_store()


def state_conn() -> sqlite3.Connection:
    path = os.getenv("TENANT_SERVER_STATE_DB_PATH", "/data/state.db")
    conn = sqlite3.connect(path, timeout=10)
    conn.execute("CREATE TABLE IF NOT EXISTS sandbox_owners (sandbox_id TEXT PRIMARY KEY, tenant_id TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)")
    conn.commit()
    return conn


def pg_state_init():
    if not psycopg or not DATABASE_URL: raise RuntimeError("Postgres state requires TENANT_SERVER_DATABASE_URL")
    with psycopg.connect(DATABASE_URL) as conn:
        conn.execute("""CREATE TABLE IF NOT EXISTS sandbox_owners (
            sandbox_id TEXT PRIMARY KEY, tenant_id TEXT NOT NULL,
            allocation_state TEXT NOT NULL DEFAULT 'allocated',
            created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
            last_activity_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
        )"""); conn.commit()


def record_sandbox(sandbox_id: str, tenant_id: str) -> None:
    if STATE_STORE_KIND == "postgres":
        pg_state_init()
        with psycopg.connect(DATABASE_URL) as conn:
            conn.execute("""INSERT INTO sandbox_owners(sandbox_id,tenant_id,allocation_state)
                VALUES(%s,%s,'allocated') ON CONFLICT (sandbox_id) DO UPDATE SET tenant_id=EXCLUDED.tenant_id, allocation_state='allocated', last_activity_at=CURRENT_TIMESTAMP""", (sandbox_id, tenant_id)); conn.commit()
        ACTIVE.labels(tenant_id).inc(); return
    with closing(state_conn()) as conn:
        conn.execute("INSERT OR REPLACE INTO sandbox_owners(sandbox_id,tenant_id) VALUES(?,?)", (sandbox_id, tenant_id)); conn.commit()
    ACTIVE.labels(tenant_id).inc()


def owned_sandbox(sandbox_id: str, tenant_id: str) -> bool:
    if STATE_STORE_KIND == "postgres":
        pg_state_init()
        with psycopg.connect(DATABASE_URL) as conn:
            return conn.execute("SELECT 1 FROM sandbox_owners WHERE sandbox_id=%s AND tenant_id=%s AND allocation_state='allocated'", (sandbox_id, tenant_id)).fetchone() is not None
    with closing(state_conn()) as conn:
        return conn.execute("SELECT 1 FROM sandbox_owners WHERE sandbox_id=? AND tenant_id=?", (sandbox_id, tenant_id)).fetchone() is not None


def remove_sandbox(sandbox_id: str, tenant_id: str) -> None:
    if STATE_STORE_KIND == "postgres":
        pg_state_init()
        with psycopg.connect(DATABASE_URL) as conn:
            cur = conn.execute("UPDATE sandbox_owners SET allocation_state='released',last_activity_at=CURRENT_TIMESTAMP WHERE sandbox_id=%s AND tenant_id=%s AND allocation_state='allocated'", (sandbox_id, tenant_id)); conn.commit()
        if cur.rowcount: ACTIVE.labels(tenant_id).dec()
        return
    with closing(state_conn()) as conn:
        removed = conn.execute("DELETE FROM sandbox_owners WHERE sandbox_id=? AND tenant_id=?", (sandbox_id, tenant_id)).rowcount; conn.commit()
    if removed: ACTIVE.labels(tenant_id).dec()


def active_count(tenant_id: str) -> int:
    if STATE_STORE_KIND == "postgres":
        pg_state_init()
        with psycopg.connect(DATABASE_URL) as conn:
            return conn.execute("SELECT count(*) FROM sandbox_owners WHERE tenant_id=%s AND allocation_state='allocated'", (tenant_id,)).fetchone()[0]
    with closing(state_conn()) as conn:
        return conn.execute("SELECT count(*) FROM sandbox_owners WHERE tenant_id=?", (tenant_id,)).fetchone()[0]


def admin_auth(value: str | None):
    if not ADMIN_TOKEN or not value or not hmac.compare_digest(value, ADMIN_TOKEN): raise HTTPException(401, "tenant server admin token required")


async def tenant_auth(authorization: str | None) -> dict[str, Any]:
    raw = validate_key(authorization); tenant = await store.get_by_key(raw)
    if not tenant: raise HTTPException(401, "invalid or disabled tenant key")
    return tenant


@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    started = time.perf_counter(); tenant = "unauthenticated"
    authorization = request.headers.get("authorization")
    if authorization and authorization.startswith("Bearer "):
        try:
            found = await store.get_by_key(authorization.removeprefix("Bearer ").strip())
            if found: tenant = found["tenant_id"]
        except Exception:
            tenant = "auth_error"
    route = request.url.path
    if "/proxy/" in route:
        route = "/v1/sandboxes/{sandbox_id}/proxy/{port}/{operation}"
    elif route.startswith("/v1/sandboxes/"):
        route = "/v1/sandboxes/{sandbox_id}"
    try:
        response = await call_next(request)
    except Exception:
        REQUESTS.labels(tenant, request.method, route, "500").inc(); raise
    REQUESTS.labels(tenant, request.method, route, str(response.status_code)).inc()
    REQUEST_LATENCY.labels(tenant, request.method, route).observe(time.perf_counter() - started)
    if "/files/upload" in request.url.path and request.headers.get("content-length"):
        UPLOADED.labels(tenant).inc(int(request.headers["content-length"]))
    return response


def scope(tenant: dict[str, Any], required: str):
    scopes = tenant.get("scopes", [])
    if isinstance(scopes, str): scopes = scopes.split(",")
    if required not in scopes: raise HTTPException(403, f"missing scope: {required}")


def denied(path: str):
    return any(path.rstrip("/").endswith(x) or f"{x}/" in path for x in DENIED_PATHS)


def forward_headers(request: Request) -> dict[str, str]:
    excluded = {"host", "content-length", "authorization", "open-sandbox-api-key"}
    headers = {k: v for k, v in request.headers.items() if k.lower() not in excluded}
    headers["OPEN-SANDBOX-API-KEY"] = UPSTREAM_KEY
    return headers


def response_headers(response: httpx.Response) -> dict[str, str]:
    keep = {"content-type", "content-disposition", "cache-control", "etag", "last-modified", "x-request-id"}
    return {k: v for k, v in response.headers.items() if k.lower() in keep}


async def limited_body(request: Request) -> AsyncIterator[bytes]:
    total = 0
    async for chunk in request.stream():
        total += len(chunk)
        if total > MAX_BODY_BYTES: raise HTTPException(413, "request body exceeds tenant server limit")
        yield chunk


async def proxy(request: Request, path: str, tenant: dict[str, Any], required_scope: str):
    scope(tenant, required_scope)
    if denied(path): raise HTTPException(404, "API route is not exposed by tenant server")
    if request.headers.get("content-length") and int(request.headers["content-length"]) > MAX_BODY_BYTES: raise HTTPException(413, "request body exceeds tenant server limit")
    outbound = app.state.http.build_request(request.method, f"{UPSTREAM}/{path.lstrip('/')}", params=request.query_params, headers=forward_headers(request), content=limited_body(request))
    upstream = await app.state.http.send(outbound, stream=True)

    async def stream():
        try:
            total = 0
            async for chunk in upstream.aiter_raw():
                total += len(chunk)
                if total > MAX_BODY_BYTES: break
                if "/files/download" in path:
                    DOWNLOADED.labels(tenant["tenant_id"]).inc(len(chunk))
                yield chunk
        finally:
            await upstream.aclose()

    return StreamingResponse(stream(), status_code=upstream.status_code, headers=response_headers(upstream))


@app.on_event("startup")
async def startup():
    app.state.http = httpx.AsyncClient(timeout=None)
    if STORE_KIND == "postgres": store._init()
    if STATE_STORE_KIND == "postgres": pg_state_init()
    if STATE_STORE_KIND == "postgres":
        with psycopg.connect(DATABASE_URL) as conn:
            rows = conn.execute("SELECT tenant_id,count(*) FROM sandbox_owners WHERE allocation_state='allocated' GROUP BY tenant_id").fetchall()
            for row in rows: ACTIVE.labels(row[0]).set(row[1])
        return
    with closing(state_conn()) as conn:
        for row in conn.execute("SELECT tenant_id,count(*) AS n FROM sandbox_owners GROUP BY tenant_id"):
            ACTIVE.labels(row[0]).set(row[1])


@app.on_event("shutdown")
async def shutdown(): await app.state.http.aclose()


@app.get("/health")
async def health(): return {"status": "ok", "store": STORE_KIND}


@app.get("/metrics")
async def metrics():
    return PlainTextResponse(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.post("/admin/tenants")
async def create_tenant(payload: TenantInput, x_tenant_server_admin_token: str | None = Header(default=None)):
    admin_auth(x_tenant_server_admin_token); raw = await store.create(payload.model_dump())
    return {"tenant_id": payload.tenant_id, "tenant_key": raw, "warning": "shown once; store securely"}


@app.get("/admin/tenants")
async def list_tenants(x_tenant_server_admin_token: str | None = Header(default=None)):
    admin_auth(x_tenant_server_admin_token); return await store.list()


@app.delete("/admin/tenants/{tenant_id}")
async def disable_tenant(tenant_id: str, x_tenant_server_admin_token: str | None = Header(default=None)):
    admin_auth(x_tenant_server_admin_token)
    if not await store.disable(tenant_id): raise HTTPException(404, "tenant not found")
    return {"tenant_id": tenant_id, "enabled": False}


@app.api_route("/v1/sandboxes", methods=["POST"])
async def create_sandbox(request: Request, authorization: str | None = Header(default=None)):
    tenant = await tenant_auth(authorization); scope(tenant, "sandbox:create")
    if active_count(tenant["tenant_id"]) >= int(tenant.get("max_concurrent_sandboxes", 3)):
        QUOTA_REJECTED.labels(tenant["tenant_id"]).inc(); raise HTTPException(429, "tenant sandbox quota exceeded")
    body = await request.body()
    response = await app.state.http.post(f"{UPSTREAM}/v1/sandboxes", params=request.query_params, headers=forward_headers(request), content=body)
    if response.status_code < 300:
        data = response.json(); sandbox_id = data.get("id")
        if sandbox_id:
            record_sandbox(sandbox_id, tenant["tenant_id"]); SANDBOX_CREATED.labels(tenant["tenant_id"]).inc()
    return JSONResponse(response.json(), status_code=response.status_code)


@app.get("/v1/sandboxes")
async def list_sandboxes(request: Request, authorization: str | None = Header(default=None)):
    tenant = await tenant_auth(authorization); scope(tenant, "sandbox:read")
    response = await app.state.http.get(f"{UPSTREAM}/v1/sandboxes", params=request.query_params, headers=forward_headers(request))
    if response.status_code >= 300: return JSONResponse(response.json(), status_code=response.status_code)
    payload = response.json()
    if isinstance(payload, list):
        payload = [item for item in payload if owned_sandbox(str(item.get("id", "")), tenant["tenant_id"])]
    elif isinstance(payload, dict) and isinstance(payload.get("items"), list):
        payload["items"] = [item for item in payload["items"] if owned_sandbox(str(item.get("id", "")), tenant["tenant_id"])]
    return JSONResponse(payload, status_code=response.status_code)


@app.api_route("/v1/sandboxes/{sandbox_id}", methods=["GET", "DELETE"])
async def sandbox_root(sandbox_id: str, request: Request, authorization: str | None = Header(default=None)):
    tenant = await tenant_auth(authorization)
    if not owned_sandbox(sandbox_id, tenant["tenant_id"]): raise HTTPException(404, "sandbox not found for tenant")
    required = "sandbox:delete" if request.method == "DELETE" else "sandbox:read"
    result = await proxy(request, f"v1/sandboxes/{sandbox_id}", tenant, required)
    if request.method == "DELETE":
        remove_sandbox(sandbox_id, tenant["tenant_id"]); SANDBOX_DELETED.labels(tenant["tenant_id"]).inc()
    return result


@app.api_route("/v1/sandboxes/{sandbox_id}/{action}", methods=["GET", "POST", "DELETE"])
async def lifecycle(sandbox_id: str, action: str, request: Request, authorization: str | None = Header(default=None)):
    tenant = await tenant_auth(authorization)
    if not owned_sandbox(sandbox_id, tenant["tenant_id"]): raise HTTPException(404, "sandbox not found for tenant")
    scope(tenant, "sandbox:delete" if request.method == "DELETE" else "sandbox:read")
    result = await proxy(request, f"v1/sandboxes/{sandbox_id}/{action}", tenant, "sandbox:delete" if request.method == "DELETE" else "sandbox:read")
    if request.method == "DELETE":
        remove_sandbox(sandbox_id, tenant["tenant_id"]); SANDBOX_DELETED.labels(tenant["tenant_id"]).inc()
    return result


@app.api_route("/v1/sandboxes/{sandbox_id}/proxy/{port}/{path:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE"])
async def sandbox_proxy(sandbox_id: str, port: int, path: str, request: Request, authorization: str | None = Header(default=None)):
    tenant = await tenant_auth(authorization)
    if not owned_sandbox(sandbox_id, tenant["tenant_id"]): raise HTTPException(404, "sandbox not found for tenant")
    required = "sandbox:files" if "/files/" in f"/{path}" else "sandbox:command"
    if required == "sandbox:command": COMMANDS.labels(tenant["tenant_id"]).inc()
    return await proxy(request, f"v1/sandboxes/{sandbox_id}/proxy/{port}/{path}", tenant, required)


@app.api_route("/{path:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE"])
async def deny_unknown(path: str):
    return JSONResponse({"detail": "API route is not exposed by tenant server", "path": "/" + path}, status_code=404)
