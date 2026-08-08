# OpenSandbox file-flow prototype

Deployment and cross-cluster installation instructions are in
[`DEPLOYMENT.md`](DEPLOYMENT.md).

This is a local frontend/backend prototype. It does not install OpenSandbox or
change the current Kubernetes cluster.

The browser calls the FastAPI backend only. The backend creates a remote
OpenSandbox, uploads `main.py` and optional input files into `/workspace`, runs
`python /workspace/main.py` through Execd, streams stdout/stderr over SSE, lists
files in the sandbox, and proxies downloads from the sandbox back to the browser.

## Run locally

```bash
cd opensandbox-demo/backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
set -a; source ../.env.example; set +a
uvicorn app:app --reload --port 8081
```

Serve `frontend/` with any static server and set `CORS_ORIGINS` accordingly. For
example:

```bash
cd opensandbox-demo/frontend
python3 -m http.server 5173
```

The prototype intentionally requires `OPENSANDBOX_EXEC_BASE_URL_TEMPLATE` and
`OPENSANDBOX_IMAGE` to be filled after the actual OpenSandbox deployment. This
avoids guessing the installed ingress/proxy endpoint or image name.

## API flow

```text
POST /api/runs                         multipart code + files
GET  /api/runs/{run_id}                status and accumulated output
GET  /api/runs/{run_id}/events         backend SSE stream
GET  /api/runs/{run_id}/files          sandbox file listing
GET  /api/runs/{run_id}/files/download sandbox file download
DELETE /api/runs/{run_id}              sandbox cleanup
```

The OpenSandbox Execd adapter follows the official `/files/upload`,
`/files/download`, `/files/search`, and `/command` APIs. The official API uses
multipart metadata plus file content for uploads, octet-stream responses for
downloads, and SSE for command output.

## Important security boundary

This is a demonstration, not a production arbitrary-code service. Before
exposing it externally, add authentication, per-user quotas, persistent run
state, an allowlist for downloadable paths, rate limiting, output truncation,
network egress policy, and a secure runtime such as gVisor/Kata/Firecracker.
