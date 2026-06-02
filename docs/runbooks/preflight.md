# Preflight Runbook

## Purpose

Provide a repeatable operator flow before any infrastructure work begins.

## Steps

1. Copy `env/azure.env.example` to a local env file such as `.env`
2. Fill in subscription, tenant, region, and access mode
3. Run `make preflight`
4. If using Azure MCP, record the actual MCP server name and validation results
5. If using CLI fallback, capture the successful command outputs in the handoff

## Expected outcomes

1. The target Azure identity is confirmed
2. The target subscription is confirmed
3. The target region is confirmed
4. A clear decision exists: `mcp` or `cli`
5. The repo is ready for Terraform and Kubernetes implementation

