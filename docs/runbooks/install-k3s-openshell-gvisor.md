# Install Path: K3s + OpenShell + gVisor

這條路線的重點不是功能完整，而是獨立驗證：

- gVisor 作為 runtime 時
- OpenShell 還剩下哪些能力
- 哪些能力會退化

## 目標

- 建立 `k3s + containerd`
- 安裝 gVisor / `RuntimeClass gvisor`
- 安裝 OpenShell
- 套用 gVisor 專用 patcher
- 驗證 L7 仍成立、filesystem policy 退化

## 安裝流程

1. 建立 K3s 叢集

```bash
make tf-init
make tf-plan
make tf-apply
./scripts/fetch-kubeconfig.sh
```

2. 安裝 gVisor

```bash
make gvisor-install
make gvisor-verify
```

3. 安裝 OpenShell

```bash
make openshell-install
make openshell-patcher-gvisor
```

4. 執行 OpenShell 驗證

```bash
make openshell-verify
```

## 預期結果

- OpenShell sandbox 能建立
- `curl GET` allowed
- `python3 GET` denied
- `curl POST` denied
- 但 filesystem policy 不再成立

## 必須知道的限制

根據本 repo 已驗證結果：

- `landlock_create_ruleset` 在 gVisor 路徑回 `ENOSYS`
- 所以 `filesystem_policy` 會退化
- 這不是安裝錯誤，而是實際 runtime 相容性限制

## Repo 內關鍵檔案

- `scripts/install-gvisor.sh`
- `scripts/install-openshell-sandbox-patcher-gvisor.sh`
- `scripts/verify-openshell-runtime.sh`
- `k8s/gvisor-runtimeclass.yaml`
- `k8s/openshell-sandbox-patcher-gvisor.yaml`
- `docs/lab-gvisor.html`

## 清理

```bash
make tf-destroy
```
