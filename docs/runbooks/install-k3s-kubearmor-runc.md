# Install Path: K3s + KubeArmor + runc

這條路線是 OpenShell 之外的獨立 runtime security 對照線。

## 最短路徑

```bash
./scripts/install-k3s-kubearmor-runc.sh
```

## 它會做什麼

1. 套用 `terraform/stacks/k3s-kubearmor-runc`
2. 抓回 kubeconfig 到 `generated/stacks/k3s-kubearmor-runc/kubeconfig`
3. 等三個節點都 `Ready`
4. 依官方 Helm 路徑安裝 KubeArmor operator
5. 套用 sample config，等待 controller / relay / daemonset 真正建立並 rollout 完成
6. 建立 demo workload，再套用 demo policy
7. 嘗試讀取 service account token，確認 block policy 是否生效

## 這條路線的關鍵安裝細節

這次修正後，腳本不是「裝完 operator 就直接跑 demo」，而是明確處理 KubeArmor 的時序：

1. `kubearmor-operator` 先用 Helm 安裝
2. `sample-config.yml` 套用後，operator 才會建立：
   - `kubearmor-controller`
   - `kubearmor-relay`
   - `kubearmor-apparmor-containerd-*`
3. 只有在這些元件全部 ready 後，才建立 `kubearmor-demo`

另外 Helm values 也改成：

- `kubearmorOperator.annotateExisting=true`

這是為了避免 workload 建立早於 enforcement 路徑 ready 時，既有 pod 完全不會被回補處理。

## 目前已驗證成功的案例

- `block-service-account-token`
  - 驗證腳本：[verify-kubearmor-runtime.sh](/Users/hwchiu/hwchiu/openqq/scripts/verify-kubearmor-runtime.sh)
  - 最新報告：[kubearmor-hardening-2026-06-08.md](/Users/hwchiu/hwchiu/openqq/testing/kubearmor-hardening-2026-06-08.md)

## 對應 Terraform Root

- `terraform/stacks/k3s-kubearmor-runc`

## 對應腳本

- `scripts/install-k3s-kubearmor-runc.sh`
- `scripts/install-kubearmor-stack.sh`
- `scripts/verify-kubearmor-runtime.sh`

## 對應 K8s Manifests

- `k8s/kubearmor-demo-nginx.yaml`
- `k8s/kubearmor-audit-etc-nginx.yaml`
- `k8s/kubearmor-block-sa-token.yaml`

## 清理

```bash
./scripts/destroy-comparison-matrix.sh
# 或單獨 destroy
source ./scripts/lib-stack.sh && terraform_destroy_stack k3s-kubearmor-runc
```
