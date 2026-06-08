# Install Path: K3s + KubeArmor + runc

這條路線和 OpenShell 無關，是獨立的 runtime security / policy 驗證線。

## 目標

- 建立 `k3s + containerd/runc`
- 安裝 KubeArmor operator
- 啟用 namespace visibility
- 套用最小化檔案規則驗證
- 驗證 telemetry / block 行為

## 適用場景

- 你要比較 OpenShell 與 KubeArmor 的能力邊界
- 你要一條不依賴 OpenShell 的 runtime security 路線
- 你想驗證 KubeArmor on K3s with runc

## 安裝流程

1. 建立 K3s 叢集

```bash
make tf-init
make tf-plan
make tf-apply
./scripts/fetch-kubeconfig.sh
```

2. 安裝 KubeArmor operator

```bash
helm repo add kubearmor https://kubearmor.github.io/charts
helm repo update kubearmor
helm --kubeconfig generated/kubeconfig upgrade --install kubearmor-operator kubearmor/kubearmor-operator -n kubearmor --create-namespace
kubectl --kubeconfig generated/kubeconfig apply -f https://raw.githubusercontent.com/kubearmor/KubeArmor/main/pkg/KubeArmorOperator/config/samples/sample-config.yml
```

3. 建立測試 workload

```bash
kubectl --kubeconfig generated/kubeconfig apply -f k8s/kubearmor-demo-nginx.yaml
kubectl --kubeconfig generated/kubeconfig rollout status deploy/kubearmor-demo -n default
```

4. 啟用 namespace visibility

```bash
kubectl --kubeconfig generated/kubeconfig annotate ns default kubearmor-visibility="process,file,network" --overwrite
```

5. 套用測試 policy

```bash
kubectl --kubeconfig generated/kubeconfig apply -f k8s/kubearmor-audit-etc-nginx.yaml
kubectl --kubeconfig generated/kubeconfig apply -f k8s/kubearmor-block-sa-token.yaml
```

## 驗證方式

- 進入 `kubearmor-demo` Pod
- 嘗試讀取 `/run/secrets/kubernetes.io/serviceaccount/token`
- 預期 `Permission denied`
- 觀察 KubeArmor log / telemetry

## Repo 內關鍵檔案

- `k8s/kubearmor-demo-nginx.yaml`
- `k8s/kubearmor-audit-etc-nginx.yaml`
- `k8s/kubearmor-block-sa-token.yaml`

## 清理

```bash
make tf-destroy
```
