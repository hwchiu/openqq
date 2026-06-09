# Failure Catalog - 2026-06-09

這份文件專門記錄 `2026-06-09` live rerun 裡所有明確失敗的案例。

原則很簡單：

- 成功就寫成功
- 失敗就寫失敗
- 每個失敗案例都至少保留：
  - 現象
  - 原始結果檔
  - 直接 log / error
  - 目前判讀

這份文件不負責美化結果，只負責把失敗留清楚。

## 版本基線

- Kubernetes: `v1.31.14+k3s1`
- Container runtime: `cri-o://1.31.13`
- Istio: `1.30.1`
- 叢集 OS: `Ubuntu 22.04`
- 驗證時間: `2026-06-09T13:07:54Z`

總表來源：
- [testing/comparison-matrix-live-2026-06-09.md](/Users/hwchiu/hwchiu/openqq/testing/comparison-matrix-live-2026-06-09.md)
- [testing/raw/comparison-matrix-live-2026-06-09/summary.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/summary.json)

## Failure 1: `k3s-gvisor` bare `RuntimeClass gvisor` probe

結果檔：
- [testing/raw/comparison-matrix-live-2026-06-09/k3s-gvisor/gvisor-runtime.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/k3s-gvisor/gvisor-runtime.json)

結果：

```json
{
  "status": "fail",
  "summary": "RuntimeClass gvisor did not produce a clean probe result"
}
```

直接證據：

```text
phase: Failed
reason: Error
ContainersReady: False
PodScheduled: True
Normal  Scheduled  Successfully assigned default/gvisor-matrix-1781008949 to worker-2
Normal  Pulled     Container image "busybox:stable" already present on machine
Normal  Created    Created container: probe
Normal  Started    Started container probe
```

判讀：

- Pod 已被排程
- container 已被建立與啟動
- 但沒有留下 `4.19.0-gvisor` 或 `gVisor-probe-OK` 這種成功證據
- 所以目前只能判成 `FAIL`

## Failure 2: `k3s-openshell-gvisor` bare `RuntimeClass gvisor` probe

結果檔：
- [testing/raw/comparison-matrix-live-2026-06-09/k3s-openshell-gvisor/gvisor-runtime.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/k3s-openshell-gvisor/gvisor-runtime.json)

結果：

```json
{
  "status": "fail",
  "summary": "RuntimeClass gvisor did not produce a clean probe result"
}
```

直接證據：

```text
phase: Failed
reason: Error
ContainersReady: False
PodScheduled: True
Normal  Scheduled  Successfully assigned default/gvisor-matrix-1781010080 to worker-1
Normal  Pulled     Container image "busybox:stable" already present on machine
Normal  Created    Created container: probe
Normal  Started    Started container probe
```

判讀：

- 現象和 `k3s-gvisor` 幾乎一致
- 也就是說，OpenShell 有沒有裝在這個 cluster 上，不影響 bare `gvisor-runtime` probe 失敗這件事

## Failure 3: `k3s-gvisor` `Istio + RuntimeClass gvisor`

結果檔：
- [testing/raw/comparison-matrix-live-2026-06-09/k3s-gvisor/istio-gvisor-sidecar.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/k3s-gvisor/istio-gvisor-sidecar.json)

結果：

```json
{
  "status": "fail",
  "summary": "Injected gVisor workload did not become Ready under Istio",
  "details": {
    "serverError": "error: timed out waiting for the condition",
    "clientError": "error: timed out waiting for the condition"
  }
}
```

直接證據：

```text
serverError: error: timed out waiting for the condition
clientError: error: timed out waiting for the condition
```

判讀：

- 一般 sidecar smoke 在同一個 cluster 是 `PASS`
- 只有當 workload 同時要求：
  - `runtimeClassName: gvisor`
  - Istio sidecar injection
- 才會失敗
- 這表示問題是 gVisor workload 與 sidecar dataplane 的組合，而不是 Istio control plane 本身

## Failure 4: `k3s-openshell-gvisor` `Istio + RuntimeClass gvisor`

結果檔：
- [testing/raw/comparison-matrix-live-2026-06-09/k3s-openshell-gvisor/istio-gvisor-sidecar.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/k3s-openshell-gvisor/istio-gvisor-sidecar.json)

結果：

```json
{
  "status": "fail",
  "summary": "Injected gVisor workload did not become Ready under Istio",
  "details": {
    "serverError": "error: timed out waiting for the condition",
    "clientError": "error: timed out waiting for the condition"
  }
}
```

判讀：

- 現象和 `k3s-gvisor` 一致
- 這代表 OpenShell 不是這個失敗的主因
- 主因仍然是 `RuntimeClass gvisor` workload 與 Istio sidecar 的組合

## Failure 5: `k3s-kubearmor-runc` process enforcement

結果檔：
- [testing/raw/comparison-matrix-live-2026-06-09/k3s-kubearmor-runc/kubearmor-process-block.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/k3s-kubearmor-runc/kubearmor-process-block.json)

結果：

```json
{
  "status": "fail",
  "summary": "KubeArmor did not block /usr/bin/sleep execution",
  "details": {
    "stdout": "",
    "stderr": "",
    "exitCode": 0
  }
}
```

直接證據：

```text
exitCode: 0
stdout: ""
stderr: ""
```

判讀：

- `/usr/bin/sleep` 成功執行
- 代表這條 process rule 在這輪沒有實際攔下目標 binary
- 這不是 audit only 的模糊狀態，而是明確沒有擋住

## Failure 6: `k3s-kubearmor-runc` network enforcement

結果檔：
- [testing/raw/comparison-matrix-live-2026-06-09/k3s-kubearmor-runc/kubearmor-network-block.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/k3s-kubearmor-runc/kubearmor-network-block.json)

結果：

```json
{
  "status": "fail",
  "summary": "KubeArmor did not block TCP egress from /usr/bin/curl"
}
```

直接證據：

```text
HTTP/1.1 200 OK
Date: Tue, 09 Jun 2026 13:07:53 GMT
Content-Type: text/html
...
exitCode: 0
```

判讀：

- `/usr/bin/curl` 的對外 TCP egress 仍成功
- 這不是 timeout，也不是 DNS 問題
- 是明確拿到 `HTTP/1.1 200 OK`
- 所以這條 network rule 在這輪沒有擋住

## 這輪沒有失敗的重點項目

為了避免只看失敗文件產生誤讀，這裡也列出同輪明確成功的項目：

1. 四套叢集 `nodes-ready`: 全部 `PASS`
2. 四套 `baseline-pod`: 全部 `PASS`
3. 四套 `Istio control plane`: 全部 `PASS`
4. 四套一般 `Istio sidecar smoke`: 全部 `PASS`
5. `k3s-openshell-runc`
   - `openshell-control-plane`: `PASS`
   - `openshell-guardrails`: `PASS`
6. `k3s-openshell-gvisor`
   - `openshell-control-plane`: `PASS`
   - `openshell-guardrails`: `PASS`
7. `k3s-kubearmor-runc`
   - `kubearmor-sa-block`: `PASS`
   - `kubearmor-file-block`: `PASS`

## 目前的誠實結論

### 可以說成功的

1. `OpenShell + runc` 是完整主線
2. `OpenShell + gVisor` 的 sandbox / guardrails 路徑在這輪可用
3. `KubeArmor` 對 secret / file 類控制在這輪有實際效果
4. Istio control plane 與一般 sidecar smoke 在四套環境都正常

### 不能說成功的

1. bare `K3s 1.31 + CRI-O 1.31 + gVisor`
2. `Istio + RuntimeClass gvisor`
3. `KubeArmor` 的 process enforcement
4. `KubeArmor` 的 network enforcement

