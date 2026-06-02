# Azure Connectivity Checklist

This checklist must be completed before any provisioning work starts.

## Objective

Confirm that the person or automation running the deployment can reach Azure, authenticate successfully, access the correct subscription, inspect quota and SKU availability, and create the required resource types.

## Preferred path

Use Azure MCP first if it is configured in the runtime where the next model will operate.

Use Azure CLI only as a fallback when Azure MCP is unavailable.

## Information required before running checks

1. Azure tenant ID
2. Azure subscription ID
3. Azure region
4. Authentication method
5. Expected identity name or service principal
6. Whether an Azure MCP server is expected to be present

## Tools expected on the operator machine

1. Azure MCP server if using the preferred path
2. `az` if CLI fallback is needed
3. `jq` is helpful but optional
4. Network path to Azure public management endpoints

## Preflight checks

### 1. Check whether Azure MCP is available

Expected result:

The runtime exposes an Azure MCP server or Azure MCP resources/tools that can query subscriptions, regions, resource groups, SKUs, and quota.

If Azure MCP is available:

1. Use Azure MCP for the remaining checks in this section
2. Record the MCP server name in the handoff notes

If Azure MCP is not available:

1. Use the Azure CLI fallback checks below

### 2. Azure CLI fallback: confirm Azure CLI is installed

Run only if Azure MCP is unavailable:

```bash
az version
```

Expected result:

The Azure CLI returns version information without error.

### 3. Azure CLI fallback: authenticate to Azure

For interactive use:

```bash
az login
```

For service principal use:

```bash
az login --service-principal \
  --username "$AZURE_CLIENT_ID" \
  --password "$AZURE_CLIENT_SECRET" \
  --tenant "$AZURE_TENANT_ID"
```

Expected result:

Login succeeds and returns account data.

### 4. Azure CLI fallback: select the target subscription

```bash
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
az account show
```

Expected result:

The returned subscription ID matches the target environment.

### 5. Azure CLI fallback: validate management-plane access

```bash
az group list --top 5
```

Expected result:

The command returns resource groups instead of authorization or connectivity failures.

### 6. Azure CLI fallback: validate region visibility

```bash
az account list-locations --output table
```

Expected result:

The target region appears in the returned location list.

### 7. Azure CLI fallback: validate VM SKU visibility in the target region

```bash
az vm list-skus \
  --location "$AZURE_REGION" \
  --resource-type virtualMachines \
  --output table
```

Expected result:

The command succeeds. If GPU nodes are required, the desired GPU-capable SKU family should be visible.

### 8. Azure CLI fallback: validate quota visibility

```bash
az vm list-usage --location "$AZURE_REGION" --output table
```

Expected result:

Quota information is readable for the target region. This is especially important if GPU SKUs are required.

### 9. Azure CLI fallback: validate required resource providers

```bash
az provider show --namespace Microsoft.Compute
az provider show --namespace Microsoft.Network
az provider show --namespace Microsoft.Storage
```

Expected result:

The commands return provider metadata without authorization errors.

### 10. Validate resource creation permission with a low-risk test

Preferred approach:

1. Confirm permission scope with platform administrators, or
2. Create a temporary test resource group only if that is allowed

Example:

```bash
az group create \
  --name "rg-connectivity-test" \
  --location "$AZURE_REGION"
```

Expected result:

The resource group is created successfully.

If this test resource is created, delete it after validation:

```bash
az group delete --name "rg-connectivity-test" --yes --no-wait
```

## Pass criteria

All of the following must be true:

1. Azure MCP is available and can inspect the target subscription, or Azure CLI fallback succeeds
2. Authentication succeeds
3. The correct subscription is active
4. The target region is visible
5. SKU and quota checks succeed
6. Required providers are readable
7. The identity can create resources, or the platform team has explicitly confirmed equivalent rights

## Common failure modes

1. Azure MCP is expected but not configured in the runtime
2. `az login` works, but the wrong tenant or subscription is active
3. The identity can read resources but cannot create them
4. GPU SKUs are unavailable in the chosen region
5. GPU quota exists in a different region only
6. Corporate proxy or firewall blocks Azure management API access
7. Resource providers are not registered or not usable by the current identity

## Handoff note for the next model

If these checks are not complete, stop before generating Terraform or Kubernetes automation. Azure connectivity is the first gate, not a later troubleshooting step.
