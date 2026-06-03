# OpenShell × Kata 驗證報告（2026-06-03）

## 結論摘要

這條實驗線已經驗證到兩個分開的事實：

1. `k3s + containerd + RuntimeClass/kata` 在 Azure `Standard_D4s_v3` 上可正常運作
2. OpenShell 在目前這個 `k3s` 路徑下，**無法**直接跑在 Kata 上

根因不是 Kata runtime 沒裝好，也不是 OpenShell gateway 壞掉，而是：

- OpenShell 在這個 lab 的 `k3s` 路徑下，仍需要把 sandbox pod patch 成 `privileged: true`
- Kata 在這個環境下對 `privileged` pod 直接回 `QMP command failed: The device is not writable: Permission denied`

所以這一輪的誠實結論是：

- `Kata runtime`：成功
- `OpenShell control plane`：成功
- `OpenShell sandbox on Kata`：被 `privileged` 相容性阻塞

## 已驗證成功的部分

### 1. Azure VM 已切到可跑 Kata 的規格

- Terraform 改為 `vm_size = "Standard_D4s_v3"`
- 三台 VM 都存在 `/dev/kvm`
- worker 端可見 `kata-runtime 3.31.0`

證據：

- [worker-1-kata-runtime.txt](/Users/hwchiu/hwchiu/openqq/testing/raw/kata-openshell-blocker-2026-06-03/worker-1-kata-runtime.txt)
- [worker-2-kata-runtime.txt](/Users/hwchiu/hwchiu/openqq/testing/raw/kata-openshell-blocker-2026-06-03/worker-2-kata-runtime.txt)
- [nodes.txt](/Users/hwchiu/hwchiu/openqq/testing/raw/kata-openshell-blocker-2026-06-03/nodes.txt)

### 2. `RuntimeClass/kata` 已可用

- `kubectl get runtimeclass kata` 成功
- `kata-verify` probe pod 成功執行
- probe pod 的 `uname` 回報 Kata guest kernel，而不是宿主 Azure kernel

證據：

- [runtimeclass-kata.yaml](/Users/hwchiu/hwchiu/openqq/testing/raw/kata-openshell-blocker-2026-06-03/runtimeclass-kata.yaml)

實際 probe 結果重點：

```text
Linux kata-verify-... 6.18.28 ...
kata-probe-ok
```

這證明不是只有 `runtimeClassName: kata` 寫在 YAML 上，而是真的進了 Kata guest kernel。

## 阻塞 OpenShell 的真正原因

我做了三組最小化矩陣對照：

1. `base image`、不加 `privileged`
2. `base image`、加 `privileged`
3. `alpine + image volume`、加 `privileged`

結果如下：

| 測試 pod | runtimeClass | privileged | image volume | 結果 |
| --- | --- | --- | --- | --- |
| `kata-base-no-priv` | `kata` | 否 | 否 | 成功 |
| `kata-base-priv` | `kata` | 是 | 否 | 失敗 |
| `kata-image-volume-probe` | `kata` | 否 | 是 | 成功 |
| `kata-alpine-priv-imagevol` | `kata` | 是 | 是 | 失敗 |
| `kata-openshell-volume-probe` | `kata` | 是 | 是 | 失敗 |

這組矩陣把問題縮得很清楚：

- 不是 `base image` 本身壞掉
- 不是 Kubernetes `image` volume 本身不能跟 Kata 一起用
- 問題出在 `privileged + kata`

失敗訊息一致：

```text
failed to create containerd task:
failed to create shim task:
QMP command failed:
The device is not writable: Permission denied
```

證據：

- [kata-base-no-priv.describe.txt](/Users/hwchiu/hwchiu/openqq/testing/raw/kata-openshell-blocker-2026-06-03/kata-base-no-priv.describe.txt)
- [kata-base-priv.describe.txt](/Users/hwchiu/hwchiu/openqq/testing/raw/kata-openshell-blocker-2026-06-03/kata-base-priv.describe.txt)
- [kata-image-volume-probe.log](/Users/hwchiu/hwchiu/openqq/testing/raw/kata-openshell-blocker-2026-06-03/kata-image-volume-probe.log)
- [kata-alpine-priv-imagevol.describe.txt](/Users/hwchiu/hwchiu/openqq/testing/raw/kata-openshell-blocker-2026-06-03/kata-alpine-priv-imagevol.describe.txt)

## OpenShell 自身的證據

OpenShell sandbox `kata-proof` 已被 kata patcher 正確改寫成：

- `runtimeClassName: kata`
- `securityContext.privileged: true`

但 pod 最後仍然失敗，原因一樣是 Kata 的 QMP 錯誤。

證據：

- [kata-proof-sandbox.yaml](/Users/hwchiu/hwchiu/openqq/testing/raw/kata-openshell-blocker-2026-06-03/kata-proof-sandbox.yaml)
- [kata-proof-pod.yaml](/Users/hwchiu/hwchiu/openqq/testing/raw/kata-openshell-blocker-2026-06-03/kata-proof-pod.yaml)
- [kata-proof-pod-describe.txt](/Users/hwchiu/hwchiu/openqq/testing/raw/kata-openshell-blocker-2026-06-03/kata-proof-pod-describe.txt)
- [kata-proof-events.txt](/Users/hwchiu/hwchiu/openqq/testing/raw/kata-openshell-blocker-2026-06-03/kata-proof-events.txt)

也就是說，現在不是 patcher 沒 patch 到，也不是 RuntimeClass 沒吃進去，而是 **OpenShell 所需的 privileged sandbox 與目前這條 Kata 路徑不相容**。

## 與其他 runtime 的對照

### `runc + OpenShell`

- 可運作
- filesystem policy 成立
- L7 / binary allowlist / hot-reload 成立

### `gVisor + OpenShell`

- 可運作
- L7 / binary allowlist / hot-reload 成立
- filesystem policy 因 `Landlock ENOSYS` 退化

### `Kata + OpenShell`

- Kata runtime 本身可運作
- OpenShell sandbox 因 `privileged` 相容性阻塞
- 所以目前無法進一步驗證 filesystem / L7 / hot-reload

## 目前可下的結論

1. 如果目標是 **功能完整落地**，目前仍應優先選 `runc + OpenShell`
2. 如果目標是 **更強 runtime 邊界**，`gVisor + OpenShell` 已有可操作結果，但要接受 filesystem policy 缺口
3. `Kata + OpenShell` 現在不能被稱為完成方案，因為它被 `privileged` 相容性卡住

## 官方文件交叉驗證後的判讀

這一輪不是只靠黑箱實驗硬猜。我另外對照了 OpenShell 官方文件，得到三個更穩的判讀：

1. 官方 security best practices 明確寫出 supervisor 啟動順序仍包含 `privileged supervisor bootstrap helpers`
2. 同一份文件也提供 `server.enableUserNamespaces=true`，但把它定位成 defense-in-depth
3. 官方 compute drivers 文件另外提供 `vm` driver

把這三點放在一起看，結論是：

- `enableUserNamespaces` 是 **額外降低 host 暴露面** 的選項
- 它不是 **直接移除 privileged bootstrap 依賴** 的保證
- 如果目標是要 OpenShell 官方支持的 VM 邊界，`vm` driver 比 Kubernetes + Kata 更接近原生設計

所以目前不應把 user namespaces 誤解成 Kata 阻塞的直接解法。

## 下一步建議

要讓 `Kata + OpenShell` 再往前，方向不應該是繼續改一般 policy YAML，而是：

1. 釐清 OpenShell 是否能在這條 `k3s` 路徑下去掉 `privileged`
2. 若不能，確認 Kata 對 `privileged` workload 的支援邊界與替代設定
3. 若這條線仍不通，則 `Kata` 可保留為 runtime 對照組，但不應作為目前 OpenShell 主路徑
4. 若目標改成「VM 邊界 + OpenShell 正式路徑」，應優先評估 OpenShell 官方 `vm` compute driver
