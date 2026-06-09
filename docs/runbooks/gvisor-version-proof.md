# gVisor 版本與證據鏈

這份文件只回答一個問題：

`k8s + CRI-O 1.31 + gVisor` 到底有沒有在這個 repo 裡被證明跑起來？

最短答案：

1. 有被**明確證明跑起來**的版本，是 `2026-06-03` 的 `K3s v1.35.5+k3s1 + containerd://2.2.3-k3s1 + RuntimeClass gvisor`
2. 到 `2026-06-09` 為止，`K3s v1.31.14+k3s1 + cri-o://1.31.13 + RuntimeClass gvisor` **沒有被這個 repo 證明裸 workload 可乾淨成功**
3. `2026-06-09` 這輪只能證明：
   - 叢集本身起得來
   - 一般 workload 起得來
   - Istio control plane 起得來
   - `OpenShell + gVisor` 的 sandbox 路徑是 `PASS`
   - 但 bare `RuntimeClass gvisor` probe 是 `FAIL`

## 已被證明成功的版本

日期：
- `2026-06-03`

環境：
- Azure `eastus`
- Ubuntu `22.04.5 LTS`
- Kernel `6.8.0-1052-azure`
- Kubernetes `v1.35.5+k3s1`
- Container runtime `containerd://2.2.3-k3s1`
- RuntimeClass `gvisor`
- OpenShell `0.0.53`

證據：
- [testing/openshell-gvisor-validation-2026-06-03.md](/Users/hwchiu/hwchiu/openqq/testing/openshell-gvisor-validation-2026-06-03.md)

這份報告裡有直接的 probe 輸出：

```text
4.19.0-gvisor
Linux version 4.19.0-gvisor #1 SMP Sun Jan 10 15:06:54 PST 2016
gVisor-probe-OK
```

這是目前 repo 內最直接、最乾淨的「gVisor 真的在跑」證據。

## 目前沒有被證明成功的版本

日期：
- `2026-06-09`

環境：
- Azure `eastus`
- Ubuntu `22.04`
- Kubernetes `v1.31.14+k3s1`
- Container runtime `cri-o://1.31.13`
- Istio `1.30.1`
- RuntimeClass `gvisor`

證據：
- [testing/comparison-matrix-live-2026-06-09.md](/Users/hwchiu/hwchiu/openqq/testing/comparison-matrix-live-2026-06-09.md)
- [testing/raw/comparison-matrix-live-2026-06-09/k3s-gvisor/gvisor-runtime.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/k3s-gvisor/gvisor-runtime.json)
- [testing/raw/comparison-matrix-live-2026-06-09/k3s-openshell-gvisor/gvisor-runtime.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/k3s-openshell-gvisor/gvisor-runtime.json)

這兩條 gVisor 路線在 `gvisor-runtime` 測試上的結果都是：

```json
{
  "status": "fail",
  "summary": "RuntimeClass gvisor did not produce a clean probe result"
}
```

更重要的是，`describeTail` 只證明了：

- Pod 被排程
- container 被建立
- container 被啟動

但**沒有** repo 內可引用的成功 log 來證明：

- guest kernel 字串真的出現
- `gVisor-probe-OK` 被印出
- probe 以乾淨成功狀態結束

所以對這個版本，正確描述只能是：

- `K3s 1.31 + CRI-O 1.31` 的 gVisor 安裝流程已被部署
- 但 bare `RuntimeClass gvisor` workload 在目前證據下是 `FAIL`
- 不能聲稱「這個版本已被證明跑起來」

## 為什麼會有這個落差

repo 內有兩個不同層次的驗證：

1. bare `RuntimeClass gvisor` probe
2. `OpenShell + gVisor` sandbox 路徑

在 `2026-06-09` 的 `CRI-O 1.31` 基線上：

- bare probe: `FAIL`
- `OpenShell control plane`: `PASS`
- `OpenShell guardrails`: `PASS`

所以目前能誠實說的是：

- `OpenShell` 透過自己的 sandbox / patcher 路徑，在這輪 `CRI-O 1.31` 上可用
- 但這**不等於** bare `gVisor RuntimeClass` 已被獨立證明可用

## 目前能證明到哪一步

### 可以證明

1. `containerd + gvisor` 在 `2026-06-03` 的版本組合中，曾經實際成功
2. `CRI-O 1.31` 路線上的 gVisor 安裝與 RuntimeClass 建立流程已執行
3. `OpenShell + gVisor + CRI-O 1.31` 的 guardrails 路徑在 `2026-06-09` 這輪是 `PASS`

### 不能證明

1. `K3s 1.31 + CRI-O 1.31` 的 bare `RuntimeClass gvisor` 已穩定成功
2. `Istio + RuntimeClass gvisor` 已可用
3. 目前 repo 內保留了 `2026-06-09` 那輪的精確 `runsc --version` 字串

## 版本資訊的已知缺口

`2026-06-09` 的腳本會在節點上執行 `runsc --version`：

- [scripts/install-gvisor-stack.sh](/Users/hwchiu/hwchiu/openqq/scripts/install-gvisor-stack.sh)

但這個輸出沒有被存成 repo 內的 raw artifact。  
因此目前文件可以誠實寫的精確版本是：

- K3s: `v1.31.14+k3s1`
- CRI-O: `1.31.13`
- gVisor 安裝來源：官方 `gvisor` apt repository

但不能補造 `runsc` 的精確套件版本。

## 對外說法建議

如果外部有人說：

> `k8s + CRI-O 1.31 + gVisor` 裝不起來，你到底用哪個版本跑起來？

最精確的回答應該是：

1. 我們**有成功證據**的是 `K3s v1.35.5+k3s1 + containerd://2.2.3-k3s1 + RuntimeClass gvisor`
2. 我們在 `2026-06-09` 也重做了 `K3s v1.31.14+k3s1 + cri-o://1.31.13`
3. 但這個 `CRI-O 1.31` 組合下，repo 目前的 live rerun 結果是 bare `gvisor-runtime` `FAIL`
4. 所以我們不會聲稱「`K3s 1.31 + CRI-O 1.31 + gVisor` 已被這個 repo 證明成功」

