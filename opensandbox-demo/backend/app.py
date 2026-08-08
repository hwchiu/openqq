"""Small OpenSandbox integration prototype.

The browser talks only to this API. OpenSandbox credentials and the sandbox
endpoint stay server-side. The OpenSandbox endpoint paths are deliberately
kept in one adapter so they can be adjusted to the installed server version.
"""
from __future__ import annotations

import asyncio
import json
import os
import re
import time
import uuid
from dataclasses import dataclass, field
from pathlib import PurePosixPath
from typing import Any, AsyncIterator

import httpx
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse, Response, StreamingResponse


SERVER = os.getenv("OPENSANDBOX_SERVER_URL", "http://localhost:8080").rstrip("/")
API_KEY = os.getenv("OPENSANDBOX_API_KEY", "")
EXEC_TOKEN = os.getenv("OPENSANDBOX_EXECD_TOKEN", "")
EXEC_BASE_TEMPLATE = os.getenv("OPENSANDBOX_EXEC_BASE_URL_TEMPLATE", "").rstrip("/")
IMAGE = os.getenv("OPENSANDBOX_IMAGE", "")
MAX_CODE_BYTES = int(os.getenv("MAX_CODE_BYTES", "65536"))
MAX_FILE_BYTES = int(os.getenv("MAX_FILE_BYTES", "10485760"))
RUN_TIMEOUT_MS = int(os.getenv("RUN_TIMEOUT_MS", "60000"))
RUN_TTL_SECONDS = int(os.getenv("RUN_TTL_SECONDS", "900"))
DEMO_ACCESS_TOKEN = os.getenv("DEMO_ACCESS_TOKEN", "")
FRONTEND_INDEX = os.getenv("FRONTEND_INDEX", "/app/frontend/index.html")
OPENSANDBOX_POOL_REF = os.getenv("OPENSANDBOX_POOL_REF", "")
EGRESS_PORT = int(os.getenv("OPENSANDBOX_EGRESS_PORT", "18080"))
EGRESS_TOKEN = os.getenv("OPENSANDBOX_EGRESS_TOKEN", "")
EGRESS_BASELINE = json.loads(
    os.getenv(
        "OPENSANDBOX_EGRESS_BASELINE",
        '{"defaultAction":"deny","egress":[{"action":"allow","target":"opensandbox-server.opensandbox-system.svc.cluster.local"}]}',
    )
)
EGRESS_ALLOWED_FQDNS = {
    value.strip().lower()
    for value in os.getenv("OPENSANDBOX_EGRESS_ALLOWED_FQDNS", "").split(",")
    if value.strip()
}
EGRESS_BASELINE_FQDNS = {
    rule.get("target")
    for rule in EGRESS_BASELINE.get("egress", [])
    if rule.get("action") == "allow" and rule.get("target")
}

app = FastAPI(title="OpenSandbox Python Runner", version="0.1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv("CORS_ORIGINS", "http://localhost:5173").split(","),
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def demo_auth(request, call_next):
    if request.url.path.startswith("/api/") and DEMO_ACCESS_TOKEN:
        supplied = request.headers.get("x-demo-token") or request.query_params.get("token")
        if supplied != DEMO_ACCESS_TOKEN:
            return JSONResponse({"detail": "X-Demo-Token is required"}, status_code=401)
    return await call_next(request)


@dataclass
class Run:
    id: str
    code: bytes
    files: list[tuple[str, bytes]]
    status: str = "queued"
    sandbox_id: str | None = None
    stdout: str = ""
    stderr: str = ""
    exit_code: int | None = None
    error: str | None = None
    command_history: list[dict[str, Any]] = field(default_factory=list)
    created_at: float = field(default_factory=time.time)
    events: asyncio.Queue[dict[str, Any]] = field(default_factory=asyncio.Queue)
    busy: bool = False


runs: dict[str, Run] = {}


def auth_headers() -> dict[str, str]:
    return {"OPEN-SANDBOX-API-KEY": API_KEY} if API_KEY else {}


def exec_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {EXEC_TOKEN}"} if EXEC_TOKEN else {}


def egress_headers() -> dict[str, str]:
    return {"OPENSANDBOX-EGRESS-AUTH": EGRESS_TOKEN} if EGRESS_TOKEN else {}


def validate_fqdn(target: Any) -> str:
    if not isinstance(target, str) or not target or len(target) > 253:
        raise HTTPException(400, "target must be a valid FQDN")
    target = target.strip().lower()
    if "://" in target or "/" in target or target.startswith("."):
        raise HTTPException(400, "target must be an FQDN, not a URL")
    if any(ch.isspace() for ch in target) or re.fullmatch(r"[0-9a-f:.]+(?:/[0-9]+)?", target):
        raise HTTPException(400, "IP and CIDR targets are not accepted; use an FQDN")
    if not re.fullmatch(r"(\*\.)?[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?", target):
        raise HTTPException(400, "target must be a valid FQDN")
    return target


def workspace_path(name: str) -> str:
    """Map an uploaded browser filename into the sandbox workspace safely."""
    name = name.replace("\\", "/")
    base = PurePosixPath(name).name
    if not base or base in {".", ".."} or base.startswith("."):
        raise HTTPException(400, f"invalid filename: {name!r}")
    if len(base) > 128 or not re.fullmatch(r"[A-Za-z0-9._-]+", base):
        raise HTTPException(400, f"filename is not allowed: {base!r}")
    return f"/workspace/{base}"


def exec_base(sandbox_id: str) -> str:
    if not EXEC_BASE_TEMPLATE:
        raise RuntimeError(
            "OPENSANDBOX_EXEC_BASE_URL_TEMPLATE is required after deployment; "
            "it must resolve to the sandbox Execd HTTP endpoint"
        )
    return EXEC_BASE_TEMPLATE.format(sandbox_id=sandbox_id).rstrip("/")


async def emit(run: Run, event: dict[str, Any]) -> None:
    await run.events.put(event)


class OpenSandboxClient:
    def __init__(self, client: httpx.AsyncClient):
        self.client = client

    async def create(self) -> dict[str, Any]:
        if not IMAGE and not OPENSANDBOX_POOL_REF:
            raise RuntimeError("OPENSANDBOX_IMAGE is not configured")
        request: dict[str, Any] = {
            "timeout": RUN_TTL_SECONDS,
            "metadata": {"source": "opensandbox-demo", "purpose": "file-transfer"},
        }
        if OPENSANDBOX_POOL_REF:
            # The Pool CRD supplies the image, entrypoint, execd and resources.
            request["extensions"] = {"poolRef": OPENSANDBOX_POOL_REF}
        else:
            request.update({
                "image": {"uri": IMAGE},
                "entrypoint": ["tail", "-f", "/dev/null"],
                "resourceLimits": {"cpu": "500m", "memory": "512Mi"},
                "env": {"PYTHONUNBUFFERED": "1"},
            })
        for attempt in range(6):
            try:
                response = await self.client.post(
                    f"{SERVER}/v1/sandboxes",
                    headers=auth_headers(),
                    json=request,
                    timeout=60,
                )
                response.raise_for_status()
                return response.json()
            except httpx.HTTPStatusError as exc:
                if exc.response.status_code not in {409, 429, 500, 502, 503, 504} or attempt == 5:
                    raise
                await asyncio.sleep(min(2**attempt, 8))
        raise RuntimeError("sandbox provisioning retries exhausted")

    async def upload(self, sandbox_id: str, path: str, content: bytes) -> None:
        base = exec_base(sandbox_id)
        metadata = json.dumps({"path": path, "mode": 600})
        response = await self.client.post(
            f"{base}/files/upload",
            headers=exec_headers(),
            files={
                "metadata": ("metadata", metadata, "application/json"),
                "file": ("file", content, "application/octet-stream"),
            },
            timeout=60,
        )
        response.raise_for_status()

    async def command_events(self, sandbox_id: str, command: str) -> AsyncIterator[dict[str, Any]]:
        base = exec_base(sandbox_id)
        async with self.client.stream(
            "POST",
            f"{base}/command",
            headers={**exec_headers(), "Accept": "text/event-stream"},
            json={"command": command, "cwd": "/workspace", "background": False, "timeout": RUN_TIMEOUT_MS},
            timeout=None,
        ) as response:
            response.raise_for_status()
            event_name = "message"
            data: list[str] = []
            async for line in response.aiter_lines():
                if line.startswith("event:"):
                    event_name = line[6:].strip()
                elif line.startswith("data:"):
                    data.append(line[5:].strip())
                elif line.strip() and not data:
                    try:
                        payload = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    if not isinstance(payload, dict):
                        payload = {"text": str(payload)}
                    yield {"type": str(payload.get("type", event_name)).lower(), "data": payload}
                elif not line and data:
                    raw = "\n".join(data)
                    try:
                        payload: Any = json.loads(raw)
                    except json.JSONDecodeError:
                        payload = {"text": raw}
                    if not isinstance(payload, dict):
                        payload = {"text": str(payload)}
                    payload_type = str(payload.get("type", event_name)).lower()
                    yield {"type": payload_type, "data": payload}
                    event_name, data = "message", []

    async def reset_workspace(self, sandbox_id: str) -> None:
        # Pool pods survive allocation changes, so remove all prior session data
        # before uploading the next run's files.
        async for _ in self.command_events(
            sandbox_id,
            "find /workspace -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +",
        ):
            pass

    async def download(self, sandbox_id: str, path: str) -> httpx.Response:
        response = await self.client.get(
            f"{exec_base(sandbox_id)}/files/download",
            params={"path": path},
            headers=exec_headers(),
            timeout=60,
        )
        response.raise_for_status()
        return response

    async def search(self, sandbox_id: str) -> Any:
        response = await self.client.get(
            f"{exec_base(sandbox_id)}/files/search",
            params={"path": "/workspace", "pattern": "**"},
            headers=exec_headers(),
            timeout=30,
        )
        response.raise_for_status()
        return response.json()

    async def delete(self, sandbox_id: str) -> None:
        response = await self.client.delete(
            f"{SERVER}/v1/sandboxes/{sandbox_id}", headers=auth_headers(), timeout=30
        )
        if response.status_code not in (200, 202, 204, 404):
            response.raise_for_status()

    async def egress_endpoint(self, sandbox_id: str) -> tuple[str, dict[str, str]]:
        response = await self.client.get(
            f"{SERVER}/v1/sandboxes/{sandbox_id}/endpoints/{EGRESS_PORT}",
            params={"use_server_proxy": "true"},
            headers=auth_headers(),
            timeout=30,
        )
        response.raise_for_status()
        data = response.json()
        endpoint = data["endpoint"].rstrip("/")
        if not endpoint.startswith(("http://", "https://")):
            endpoint = f"http://{endpoint}"
        return endpoint, {**data.get("headers", {}), **egress_headers()}

    async def get_egress(self, sandbox_id: str) -> Any:
        endpoint, headers = await self.egress_endpoint(sandbox_id)
        response = await self.client.get(f"{endpoint}/policy", headers=headers, timeout=30)
        response.raise_for_status()
        return response.json()

    async def replace_egress(self, sandbox_id: str, policy: dict[str, Any]) -> Any:
        endpoint, headers = await self.egress_endpoint(sandbox_id)
        response = await self.client.post(
            f"{endpoint}/policy",
            headers={**headers, "Content-Type": "application/json"},
            json=policy,
            timeout=30,
        )
        response.raise_for_status()
        return response.json()

    async def patch_egress(self, sandbox_id: str, rules: list[dict[str, str]]) -> Any:
        endpoint, headers = await self.egress_endpoint(sandbox_id)
        response = await self.client.patch(
            f"{endpoint}/policy",
            headers={**headers, "Content-Type": "application/json"},
            json=rules,
            timeout=30,
        )
        response.raise_for_status()
        return response.json()

    async def remove_egress(self, sandbox_id: str, targets: list[str]) -> Any:
        endpoint, headers = await self.egress_endpoint(sandbox_id)
        response = await self.client.request(
            "DELETE",
            f"{endpoint}/policy",
            headers={**headers, "Content-Type": "application/json"},
            json=targets,
            timeout=30,
        )
        response.raise_for_status()
        return response.json()


async def execute_run(run: Run, create_sandbox: bool = True) -> None:
    try:
        run.busy = True
        run.status = "creating" if create_sandbox else "uploading"
        await emit(run, {"type": "status", "status": run.status})
        async with httpx.AsyncClient() as http:
            client = OpenSandboxClient(http)
            if create_sandbox:
                created = await client.create()
                run.sandbox_id = created["id"]
            if not run.sandbox_id:
                raise RuntimeError("sandbox is not ready")
            run.status = "uploading"
            await emit(run, {"type": "status", "status": run.status, "sandbox_id": run.sandbox_id})
            if create_sandbox:
                await client.reset_workspace(run.sandbox_id)
                if EGRESS_TOKEN:
                    await client.replace_egress(run.sandbox_id, EGRESS_BASELINE)
            await client.upload(run.sandbox_id, "/workspace/main.py", run.code)
            for name, content in run.files:
                await client.upload(run.sandbox_id, workspace_path(name), content)
            run.status = "running"
            await emit(run, {"type": "status", "status": run.status})
            async for event in client.command_events(run.sandbox_id, "python /workspace/main.py"):
                payload = event.get("data") if isinstance(event.get("data"), dict) else {}
                text = payload.get("text") or payload.get("output") or payload.get("message") or ""
                channel = str(payload.get("stream", payload.get("channel", event.get("type", "stdout")))).lower()
                if text and channel in {"stdout", "stderr"}:
                    if "err" in channel:
                        run.stderr += str(text)
                    else:
                        run.stdout += str(text)
                if "exit" in payload:
                    run.exit_code = int(payload["exit"])
                elif "exit_code" in payload and payload["exit_code"] is not None:
                    run.exit_code = int(payload["exit_code"])
                if text and channel in {"stdout", "stderr"}:
                    await emit(run, {"type": "output", "stream": channel, "text": str(text), "raw": event})
            run.status = "completed" if (run.exit_code in (None, 0)) else "failed"
            await emit(run, {"type": "status", "status": run.status, "exit_code": run.exit_code})
    except Exception as exc:  # surfaced to the UI; never expose stack traces
        run.status = "failed"
        run.error = str(exc)
        await emit(run, {"type": "error", "message": run.error})
    finally:
        run.busy = False


async def execute_command(run: Run, command: str) -> dict[str, Any]:
    if not run.sandbox_id:
        raise HTTPException(409, "sandbox is not ready")
    stdout, stderr, exit_code = [], [], None
    async with httpx.AsyncClient() as http:
        client = OpenSandboxClient(http)
        async for event in client.command_events(run.sandbox_id, command):
            payload = event.get("data") if isinstance(event.get("data"), dict) else {}
            channel = str(payload.get("stream", payload.get("channel", event.get("type", "stdout")))).lower()
            text = payload.get("text") or payload.get("output") or ""
            if channel == "stdout":
                stdout.append(str(text))
            elif channel == "stderr":
                stderr.append(str(text))
            if "exit" in payload:
                exit_code = int(payload["exit"])
            elif payload.get("exit_code") is not None:
                exit_code = int(payload["exit_code"])
    result = {"command": command, "stdout": "".join(stdout), "stderr": "".join(stderr), "exit_code": exit_code}
    run.command_history.append(result)
    return result


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok", "integration": "not configured" if not EXEC_BASE_TEMPLATE else "configured"}


@app.get("/", include_in_schema=False)
async def frontend() -> FileResponse:
    return FileResponse(FRONTEND_INDEX)


@app.post("/api/runs")
async def create_run(code: UploadFile = File(...), files: list[UploadFile] = File(default=[])) -> dict[str, str]:
    code_bytes = await code.read()
    if len(code_bytes) == 0 or len(code_bytes) > MAX_CODE_BYTES:
        raise HTTPException(413, f"Python code must be 1..{MAX_CODE_BYTES} bytes")
    collected: list[tuple[str, bytes]] = []
    for upload in files:
        content = await upload.read()
        if len(content) > MAX_FILE_BYTES:
            raise HTTPException(413, f"file {upload.filename!r} exceeds {MAX_FILE_BYTES} bytes")
        collected.append((upload.filename or "file", content))
    run = Run(str(uuid.uuid4()), code_bytes, collected)
    runs[run.id] = run
    asyncio.create_task(execute_run(run))
    return {"run_id": run.id, "status": run.status}


@app.post("/api/runs/{run_id}/execute")
async def execute_existing_run(run_id: str, code: UploadFile = File(...), files: list[UploadFile] = File(default=[])) -> dict[str, str]:
    run = runs.get(run_id)
    if not run or not run.sandbox_id:
        raise HTTPException(409, "sandbox session is not ready")
    if run.busy:
        raise HTTPException(409, "sandbox session is already running")
    code_bytes = await code.read()
    if len(code_bytes) == 0 or len(code_bytes) > MAX_CODE_BYTES:
        raise HTTPException(413, f"Python code must be 1..{MAX_CODE_BYTES} bytes")
    collected: list[tuple[str, bytes]] = []
    for upload in files:
        content = await upload.read()
        if len(content) > MAX_FILE_BYTES:
            raise HTTPException(413, f"file {upload.filename!r} exceeds {MAX_FILE_BYTES} bytes")
        collected.append((upload.filename or "file", content))
    run.code = code_bytes
    run.files = collected
    run.stdout = ""
    run.stderr = ""
    run.exit_code = None
    run.error = None
    run.status = "queued"
    asyncio.create_task(execute_run(run, create_sandbox=False))
    return {"run_id": run.id, "status": run.status, "sandbox_id": run.sandbox_id}


@app.get("/api/runs/{run_id}")
async def get_run(run_id: str) -> dict[str, Any]:
    run = runs.get(run_id)
    if not run:
        raise HTTPException(404, "run not found")
    return {k: getattr(run, k) for k in ("id", "status", "sandbox_id", "stdout", "stderr", "exit_code", "error", "command_history")}


@app.post("/api/runs/{run_id}/commands")
async def run_command(run_id: str, body: dict[str, Any]) -> dict[str, Any]:
    run = runs.get(run_id)
    if not run or not run.sandbox_id:
        raise HTTPException(409, "sandbox is not ready")
    if run.busy:
        raise HTTPException(409, "sandbox session is busy")
    command = body.get("command")
    if not isinstance(command, str) or not command.strip() or len(command) > 4096:
        raise HTTPException(400, "command must be 1..4096 characters")
    try:
        return await execute_command(run, command)
    except Exception as exc:
        raise HTTPException(502, f"sandbox command failed: {exc}") from exc


@app.get("/api/runs/{run_id}/egress")
async def get_run_egress(run_id: str) -> Any:
    run = runs.get(run_id)
    if not run or not run.sandbox_id:
        raise HTTPException(409, "sandbox is not ready")
    async with httpx.AsyncClient() as http:
        return await OpenSandboxClient(http).get_egress(run.sandbox_id)


@app.patch("/api/runs/{run_id}/egress")
async def patch_run_egress(run_id: str, body: dict[str, Any]) -> Any:
    run = runs.get(run_id)
    if not run or not run.sandbox_id:
        raise HTTPException(409, "sandbox is not ready")
    if body.get("action") not in {"allow", "deny"}:
        raise HTTPException(400, "action must be allow or deny")
    target = validate_fqdn(body.get("target"))
    if target not in EGRESS_ALLOWED_FQDNS:
        raise HTTPException(403, "FQDN is not in the administrator allowlist")
    async with httpx.AsyncClient() as http:
        return await OpenSandboxClient(http).patch_egress(
            run.sandbox_id, [{"action": body["action"], "target": target}]
        )


@app.delete("/api/runs/{run_id}/egress")
async def remove_run_egress(run_id: str, body: dict[str, Any]) -> Any:
    run = runs.get(run_id)
    if not run or not run.sandbox_id:
        raise HTTPException(409, "sandbox is not ready")
    target = validate_fqdn(body.get("target"))
    if target not in EGRESS_ALLOWED_FQDNS:
        raise HTTPException(403, "FQDN is not in the administrator allowlist")
    if target in EGRESS_BASELINE_FQDNS:
        raise HTTPException(403, "baseline FQDN cannot be removed by a client")
    async with httpx.AsyncClient() as http:
        return await OpenSandboxClient(http).remove_egress(run.sandbox_id, [target])


@app.get("/api/runs/{run_id}/events")
async def run_events(run_id: str) -> StreamingResponse:
    run = runs.get(run_id)
    if not run:
        raise HTTPException(404, "run not found")

    async def stream() -> AsyncIterator[str]:
        while True:
            try:
                event = await asyncio.wait_for(run.events.get(), timeout=15)
                yield f"data: {json.dumps(event)}\n\n"
                if event.get("type") in {"error"} or (event.get("type") == "status" and event.get("status") in {"completed", "failed"}):
                    break
            except asyncio.TimeoutError:
                yield ": keepalive\n\n"

    return StreamingResponse(stream(), media_type="text/event-stream")


@app.get("/api/runs/{run_id}/files")
async def list_files(run_id: str) -> Any:
    run = runs.get(run_id)
    if not run or not run.sandbox_id:
        raise HTTPException(409, "sandbox is not ready")
    async with httpx.AsyncClient() as http:
        return await OpenSandboxClient(http).search(run.sandbox_id)


@app.get("/api/runs/{run_id}/files/download")
async def download_file(run_id: str, path: str) -> StreamingResponse:
    run = runs.get(run_id)
    if not run or not run.sandbox_id:
        raise HTTPException(409, "sandbox is not ready")
    if not path.startswith("/workspace/") or ".." in PurePosixPath(path).parts:
        raise HTTPException(400, "only files under /workspace can be downloaded")
    filename = PurePosixPath(path).name

    async def stream_file() -> AsyncIterator[bytes]:
        async with httpx.AsyncClient() as http:
            async with http.stream(
                "GET",
                f"{exec_base(run.sandbox_id)}/files/download",
                params={"path": path},
                headers=exec_headers(),
                timeout=60,
            ) as response:
                response.raise_for_status()
                async for chunk in response.aiter_bytes():
                    yield chunk

    return StreamingResponse(
        stream_file(),
        media_type="application/octet-stream",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@app.delete("/api/runs/{run_id}")
async def delete_run(run_id: str) -> JSONResponse:
    run = runs.get(run_id)
    if not run:
        raise HTTPException(404, "run not found")
    if run.busy:
        raise HTTPException(409, "sandbox session is busy")
    if run.sandbox_id:
        async with httpx.AsyncClient() as http:
            client = OpenSandboxClient(http)
            if OPENSANDBOX_POOL_REF:
                await client.reset_workspace(run.sandbox_id)
                if EGRESS_TOKEN:
                    await client.replace_egress(run.sandbox_id, EGRESS_BASELINE)
            await client.delete(run.sandbox_id)
    run.status = "deleted"
    return JSONResponse({"run_id": run_id, "status": run.status})
