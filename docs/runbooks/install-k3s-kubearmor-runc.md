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
5. 套用 sample config、namespace visibility 與 demo policy
6. 嘗試讀取 service account token，確認 block policy 是否生效

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
