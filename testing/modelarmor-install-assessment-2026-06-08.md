# ModelArmor Install Assessment (2026-06-08)

## 結論

截至 2026-06-08，沒有找到可直接在 Kubernetes 叢集上執行的官方 `ModelArmor` 安裝資產。

我實際驗證了兩件事：

1. 官方文件主要把 `ModelArmor` 描述成 AI/ML/LLM workload security solution，並明講它使用 `KubeArmor` 作為 sandboxing engine  
   Source:
   - https://docs.kubearmor.io/kubearmor/use-cases/modelarmor

2. `kubearmor/modelarmor` repo 目前只有：
   - `README.md`
   - `LICENSE`
   沒有：
   - Helm chart
   - install manifest
   - operator deployment
   - release artifact
   Source:
   - https://github.com/kubearmor/modelarmor

## 實際檢查

我把 repo clone 到本機檢查：

```text
/tmp/modelarmor-check/LICENSE
/tmp/modelarmor-check/README.md
```

沒有其他 deployable 內容。

## 判讀

因此目前不能誠實宣稱：

- `ModelArmor` 已作為一個獨立產品元件被安裝到叢集中

目前能誠實宣稱的是：

- `KubeArmor` 已安裝
- `ModelArmor` 的官方敘事明確依賴 `KubeArmor`
- 可以在現有 `KubeArmor` 叢集上建立 `ModelArmor-style` lab

## 已採取的務實替代方案

為了不讓這件事停在「查無 installer」，我另外建立了一組 `ModelArmor-style` lab 資產：

- [modelarmor-lab.yaml](/Users/hwchiu/hwchiu/openqq/k8s/modelarmor-lab.yaml)
- [modelarmor-block-sa-token.yaml](/Users/hwchiu/hwchiu/openqq/k8s/modelarmor-block-sa-token.yaml)
- [modelarmor-block-shell.yaml](/Users/hwchiu/hwchiu/openqq/k8s/modelarmor-block-shell.yaml)
- [modelarmor-block-python-egress.yaml](/Users/hwchiu/hwchiu/openqq/k8s/modelarmor-block-python-egress.yaml)
- [install-modelarmor-lab.sh](/Users/hwchiu/hwchiu/openqq/scripts/install-modelarmor-lab.sh)
- [verify-modelarmor-lab.sh](/Users/hwchiu/hwchiu/openqq/scripts/verify-modelarmor-lab.sh)

這些資產的定位是：

- 不是官方 ModelArmor installer
- 是 KubeArmor-based AI workload lab
- 用來驗證 `ModelArmor-style` threat scenarios

## 狀態更新

這組 `ModelArmor-style` lab 已經實際部署到 `k3s-kubearmor-runc`。

最新驗證結果：

- workload 進入 `enforce`
- secret read 被擋
- Python HTTP egress 尚未被擋

詳見：

- [modelarmor-lab-validation-2026-06-08.md](/Users/hwchiu/hwchiu/openqq/testing/modelarmor-lab-validation-2026-06-08.md)

## 建議

如果之後社群或官方釋出正式 installer，應該再分開驗證：

1. 官方 ModelArmor 安裝流程
2. 與目前這套 `ModelArmor-style` lab 的行為差異
