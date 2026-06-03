# gVisor 上 Landlock 退化的根因報告

日期: 2026-06-03
環境: Azure `eastus` / `k3s + containerd + RuntimeClass gvisor`

## 問題

OpenShell 在 gVisor 組的 sandbox log 反覆出現:

```text
FINDING:UNKNOWN [HIGH] "Landlock Filesystem Sandbox Unavailable"
```

對應行為是:

- `filesystem.txt` 顯示 `TMP_OK`
- `filesystem.txt` 顯示 `VARTMP_OK`
- `static-baseline.txt` 可列出 `/`

也就是 `filesystem_policy` 沒有成立。

## 假設

要分清楚這是:

1. OpenShell policy 下發失敗
2. OpenShell supervisor bug
3. gVisor 沒有提供 Landlock syscall / 子系統

## 實驗方法

在同一個叢集內建立兩個最小 Pod，內容完全相同，唯一差異是 runtime:

1. `landlock-runc-test` 使用預設 runtime
2. `landlock-gvisor-test` 使用 `runtimeClassName: gvisor`

兩個 Pod 都執行同一段 Python 程式，只做一件事:

- 直接呼叫 `landlock_create_ruleset(..., LANDLOCK_CREATE_RULESET_VERSION)` syscall

這個 syscall 的目的不是套 policy，而是先 probe Landlock ABI 版本。

如果 kernel / runtime 支援 Landlock，應回傳 ABI 版本，例如 `4`。
如果不支援，常見結果是 `ENOSYS`。

## 實驗結果

### runc 組

檔案:

- [runc-landlock-syscall.txt](/Users/hwchiu/hwchiu/openqq/testing/raw/landlock-root-cause-2026-06-03/runc-landlock-syscall.txt)

內容:

```text
ret=4
errno=0
errno_name=NONE
```

解讀:

- `landlock_create_ruleset` syscall 成功
- ABI 版本是 `4`
- 這和 runc 基準組能正常套用 Landlock 的行為一致

### gVisor 組

檔案:

- [gvisor-landlock-syscall.txt](/Users/hwchiu/hwchiu/openqq/testing/raw/landlock-root-cause-2026-06-03/gvisor-landlock-syscall.txt)

內容:

```text
ret=-1
errno=38
errno_name=ENOSYS
```

解讀:

- `ENOSYS` 表示 syscall 不存在 / 未實作
- 這不是 OpenShell policy 寫錯，也不是 OpenShell 沒送到 sandbox
- 問題發生在更底層：gVisor runtime 沒有提供這條 Landlock syscall 路徑

## 與 OpenShell log 的對應

OpenShell sandbox log 的:

```text
FINDING:UNKNOWN [HIGH] "Landlock Filesystem Sandbox Unavailable"
```

現在可以直接解釋成:

- supervisor 不是誤判
- 它在 gVisor 內 probe Landlock 時，底層 runtime 回的就是「沒有這個 syscall」

所以 `Landlock Filesystem Sandbox Unavailable` 是符合實驗結果的。

## 與 gVisor 官方文件的對照

gVisor 官方 compatibility 文件明確說明:

- gVisor 只實作 Linux syscall ABI 的一個子集
- 不可避免會有未實作的功能與相容性缺口

來源:

- gVisor Applications compatibility: https://gvisor.dev/docs/user_guide/compatibility/

本次實驗把這個抽象敘述落到具體事實：

- 在我們的環境裡，`landlock_create_ruleset` 就是其中一個未實作的 syscall 路徑

## 最終結論

最精準的根因描述是:

1. gVisor 組的 OpenShell filesystem policy 退化，不是因為 OpenShell policy delivery 失敗
2. 也不是因為 sandbox 沒有起來
3. 根因是 `landlock_create_ruleset` 在 gVisor 內回 `ENOSYS`
4. 因此 OpenShell supervisor 無法建立 Landlock filesystem sandbox
5. 所以 OpenShell 在 gVisor 上目前只能保留 network / L7 / hot-reload 這些不依賴 Landlock 的能力

## 對設計的意義

這代表目前的兩條 runtime 路徑應該被視為兩種不同取向，而不是單純升級關係:

- `runc` 路徑: OpenShell filesystem + network + L7 全功能
- `gVisor` 路徑: gVisor 增加 kernel 邊界，但 OpenShell filesystem policy 缺失

如果需求是:

- 重視 OpenShell 的 filesystem enforcement，保留 `runc` 比較合理
- 重視更強的 runtime/kernel 邊界，`gVisor` 有價值，但要接受 filesystem policy 退化
