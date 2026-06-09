# ModelArmor-Style Lab

這不是官方 `ModelArmor` installer。

目前公開的 `kubearmor/modelarmor` repo 沒有提供可直接部署的：

- Helm chart
- operator manifest
- release artifact

所以這個 repo 採用的是一條務實路徑：

- 在現有 `k3s-kubearmor-runc` 叢集上
- 建立一個 `modelarmor-lab` namespace
- 放入一個 AI-like demo workload
- 用 KubeArmor policies 去模擬 `ModelArmor-style` runtime constraints

## 安裝

```bash
KUBECONFIG_PATH=generated/stacks/k3s-kubearmor-runc/kubeconfig ./scripts/install-modelarmor-lab.sh
```

## 驗證

```bash
KUBECONFIG_PATH=generated/stacks/k3s-kubearmor-runc/kubeconfig ./scripts/verify-modelarmor-lab.sh
```

最新實測報告：

- [modelarmor-lab-validation-2026-06-08.md](/Users/hwchiu/hwchiu/openqq/testing/modelarmor-lab-validation-2026-06-08.md)

## 元件

- [modelarmor-lab.yaml](/Users/hwchiu/hwchiu/openqq/k8s/modelarmor-lab.yaml)
- [modelarmor-payload-server.yaml](/Users/hwchiu/hwchiu/openqq/k8s/modelarmor-payload-server.yaml)
- [modelarmor-block-sa-token.yaml](/Users/hwchiu/hwchiu/openqq/k8s/modelarmor-block-sa-token.yaml)
- [modelarmor-block-shell.yaml](/Users/hwchiu/hwchiu/openqq/k8s/modelarmor-block-shell.yaml)
- [modelarmor-block-python-egress.yaml](/Users/hwchiu/hwchiu/openqq/k8s/modelarmor-block-python-egress.yaml)

## 目的

這組 lab 的重點不是聲稱「已安裝官方 ModelArmor」，而是先建立：

1. AI workload 的獨立 namespace
2. 對應的 runtime policy constraints
3. 後續可以持續擴充的 AI attack scenarios

## 目前已知結果

截至 2026-06-08：

1. workload 已進入 `enforce` 狀態
2. service account token 讀取可被擋下
3. Python subprocess shell escape 目前仍可成功
4. Python 對外 HTTP egress 目前仍可成功
5. payload staging 到 `/tmp` 目前仍可成功
6. `pip install` 到 `/tmp` 目前仍可成功
7. `pip install + import` 目前仍可成功
8. `pickle` 可直接帶出 code execution
9. in-cluster `download-and-exec` 目前仍可成功

所以這個 lab 現在比較像：

- `ModelArmor-style baseline`

而不是：

- 已完整具備 AI sandbox 防護能力

## 常用測試命令

```bash
./scripts/tests/modelarmor-secret-read.sh generated/stacks/k3s-kubearmor-runc/kubeconfig
./scripts/tests/modelarmor-shell-escape.sh generated/stacks/k3s-kubearmor-runc/kubeconfig
./scripts/tests/modelarmor-python-egress.sh generated/stacks/k3s-kubearmor-runc/kubeconfig
./scripts/tests/modelarmor-payload-stage.sh generated/stacks/k3s-kubearmor-runc/kubeconfig
bash ./scripts/tests/modelarmor-pip-install.sh generated/stacks/k3s-kubearmor-runc/kubeconfig
bash ./scripts/tests/modelarmor-pip-import.sh generated/stacks/k3s-kubearmor-runc/kubeconfig
bash ./scripts/tests/modelarmor-pickle-rce.sh generated/stacks/k3s-kubearmor-runc/kubeconfig
bash ./scripts/tests/modelarmor-download-exec.sh generated/stacks/k3s-kubearmor-runc/kubeconfig
```
