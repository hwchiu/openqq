# Install Path: K3s + OpenShell + runc

這是目前 repo 中最完整、最穩定的安裝主線。

## 目標

- 建立 `k3s + containerd/runc`
- 安裝 `agent-sandbox`
- 安裝 `OpenShell`
- 套用 k3s 相容性 patcher
- 驗證 OpenShell sandbox、L7、filesystem policy

## 適用場景

- 你要完整驗證 OpenShell 核心能力
- 你需要目前最接近正式可落地的路線
- 你要使用本 repo 已完成的 FUSE / CSI / policy 測試

## 安裝流程

1. 建立 K3s 叢集

```bash
make tf-init
make tf-plan
make tf-apply
./scripts/fetch-kubeconfig.sh
kubectl --kubeconfig generated/kubeconfig get nodes -o wide
```

2. 安裝 OpenShell stack

```bash
make openshell-install
```

這一步會：

- 安裝 OpenShell gateway
- 安裝 Agent Sandbox controller / CRD
- 安裝預設 patcher

3. 驗證 OpenShell runtime

```bash
make openshell-verify
```

## 驗證成功條件

- `kubectl -n openshell get pods` 全部 `Running`
- OpenShell sandbox 可建立
- `curl GET` allowed
- `python3 GET` denied
- `curl POST` denied
- `/tmp` 可寫、`/var/tmp` denied

## Repo 內關鍵檔案

- `scripts/install-openshell-stack.sh`
- `scripts/install-openshell-sandbox-patcher.sh`
- `scripts/verify-openshell-runtime.sh`
- `k8s/openshell-values.yaml`
- `k8s/openshell-sandbox-patcher.yaml`
- `docs/lab.html`

## 後續可接的延伸

- `docs/runbooks/fuse-lab.md`
- `docs/runbooks/azurefile-csi-lab.md`

## 清理

```bash
make tf-destroy
```
