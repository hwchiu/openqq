# ModelArmor-Style Lab Validation (2026-06-08)

這份報告記錄在 `k3s-kubearmor-runc` 上部署 `ModelArmor-style` lab 後的實測結果。

## 前提

這不是官方 `ModelArmor` installer。

原因已寫在：

- [modelarmor-install-assessment-2026-06-08.md](/Users/hwchiu/hwchiu/openqq/testing/modelarmor-install-assessment-2026-06-08.md)

這裡驗證的是：

- 一個 AI-like Python workload
- 是否能被 KubeArmor 以 `ModelArmor-style` 方式約束

## 部署內容

- namespace: `modelarmor-lab`
- workload: `modelarmor-demo`
- image: `python:3.11-slim`
- fixture service: `payload-server`
- policies:
  - `modelarmor-block-sa-token`
  - `modelarmor-block-shell`
  - `modelarmor-block-python-egress`

對應檔案：

- [modelarmor-lab.yaml](/Users/hwchiu/hwchiu/openqq/k8s/modelarmor-lab.yaml)
- [modelarmor-payload-server.yaml](/Users/hwchiu/hwchiu/openqq/k8s/modelarmor-payload-server.yaml)
- [modelarmor-block-sa-token.yaml](/Users/hwchiu/hwchiu/openqq/k8s/modelarmor-block-sa-token.yaml)
- [modelarmor-block-shell.yaml](/Users/hwchiu/hwchiu/openqq/k8s/modelarmor-block-shell.yaml)
- [modelarmor-block-python-egress.yaml](/Users/hwchiu/hwchiu/openqq/k8s/modelarmor-block-python-egress.yaml)

## 實測結果

### 1. workload 是否進入 enforce 狀態

結果：`PASS`

從 pod 內讀到：

```text
kubearmor-modelarmor-lab-modelarmor-demo-python (enforce)
```

證據：

- [attr.txt](/Users/hwchiu/hwchiu/openqq/testing/raw/modelarmor-lab-2026-06-08/attr.txt)

### 2. service account token 讀取

結果：`PASS`

Python 嘗試讀取：

- `/run/secrets/kubernetes.io/serviceaccount/token`

結果：

- `PermissionError: [Errno 13] Permission denied`

證據：

- [token.stderr](/Users/hwchiu/hwchiu/openqq/testing/raw/modelarmor-lab-2026-06-08/token.stderr)

### 3. Python subprocess shell escape

結果：`FAIL`

Python 嘗試：

- `subprocess.run(["/bin/sh","-c","echo escaped"], check=True)`

結果：

- shell 成功執行
- stdout 為 `escaped`

證據：

- [shell-escape.json](/Users/hwchiu/hwchiu/openqq/testing/raw/modelarmor-lab-2026-06-08/shell-escape.json)

### 4. Python 對外 HTTP egress

結果：`FAIL`

Python 嘗試：

- `urllib.request.urlopen("http://example.com")`

結果：

- 成功回傳 `200`

證據：

- [egress.stdout](/Users/hwchiu/hwchiu/openqq/testing/raw/modelarmor-lab-2026-06-08/egress.stdout)
- [egress.stderr](/Users/hwchiu/hwchiu/openqq/testing/raw/modelarmor-lab-2026-06-08/egress.stderr)
- [python-egress.json](/Users/hwchiu/hwchiu/openqq/testing/raw/modelarmor-lab-2026-06-08/python-egress.json)

### 5. Payload staging to `/tmp`

結果：`DEGRADED`

Python 嘗試：

- 從 `http://example.com` 下載 32 bytes
- 寫入 `/tmp/payload.bin`

結果：

- 下載成功
- staging 成功

證據：

- [payload-stage.json](/Users/hwchiu/hwchiu/openqq/testing/raw/modelarmor-lab-2026-06-08/payload-stage.json)

### 6. `pip install` 到 `/tmp`

結果：`DEGRADED`

Python 嘗試：

- `python3 -m pip install colorama==0.4.6 --target /tmp/pip-target`

結果：

- 套件下載成功
- 套件安裝成功

證據：

- [pip-install.json](/Users/hwchiu/hwchiu/openqq/testing/raw/modelarmor-lab-2026-06-08/pip-install.json)

### 7. `pip install + import`

結果：`DEGRADED`

Python 嘗試：

- `pip install colorama==0.4.6 --target /tmp/pip-import-target`
- 將 target 目錄插入 `sys.path`
- 立刻 `import colorama`

結果：

- 套件下載成功
- 套件安裝成功
- runtime import 成功

證據：

- [pip-import.json](/Users/hwchiu/hwchiu/openqq/testing/raw/modelarmor-lab-2026-06-08/pip-import.json)

### 8. `pickle` 反序列化帶出的 code execution

結果：`FAIL`

Python 嘗試：

- 建立惡意 pickle payload
- payload 透過 `os.system()` 寫入 `/tmp/pickle-proof`

結果：

- code execution 成功
- `/tmp/pickle-proof` 內容為 `pickle-rce`

證據：

- [pickle-rce.json](/Users/hwchiu/hwchiu/openqq/testing/raw/modelarmor-lab-2026-06-08/pickle-rce.json)

### 9. in-cluster `download-and-exec`

結果：`FAIL`

Python 嘗試：

- 從 `payload-server.modelarmor-lab.svc.cluster.local` 下載 `payload.sh`
- 寫到 `/tmp/downloaded-payload.sh`
- 以 `/bin/sh` 執行下載回來的 script

結果：

- script 成功執行
- stdout 出現 `payload-ok`
- proof file 內容為 `payload-exec`

證據：

- [download-exec.json](/Users/hwchiu/hwchiu/openqq/testing/raw/modelarmor-lab-2026-06-08/download-exec.json)

## 重要發現

我另外直接檢查 KubeArmor 寫進節點的 AppArmor profile：

- [apparmor-profile.txt](/Users/hwchiu/hwchiu/openqq/testing/raw/modelarmor-lab-2026-06-08/apparmor-profile.txt)

實際 profile 內容顯示：

- `deny /bin/sh x`
- `deny network tcp`

但 runtime 實測仍然出現：

- Python subprocess shell escape 成功
- Python HTTP egress 成功

這代表目前問題不只是「policy 沒建立」，而是：

- policy 已被編進 profile
- 但在這個 workload / runtime 路徑下，實際 enforcement 沒有完全符合預期

這點和前面 `kubearmor-demo` 上看到的現象一致：

- file 類規則較穩
- process / network 類規則需要更深入驗證

## 目前結論

目前這組 `ModelArmor-style` lab 可以誠實宣稱：

1. AI-like workload 已被 KubeArmor 放進 enforce 狀態
2. secret read guardrail 已成立

但不能宣稱：

1. Python-based outbound egress 已被成功限制
2. Python subprocess shell escape 已被成功限制
3. payload staging 已被成功限制
4. `pip install` / tool bootstrap 已被成功限制
5. `pip install + import` / agent self-extension 已被成功限制
6. `pickle` 類不可信模型載入已被成功限制
7. `download-and-exec` 鏈已被成功限制
8. shell / tool-use / model download 這些 AI threat scenarios 已完整驗證

## 下一步

如果要更像 `ModelArmor` 場景，接下來最值得補的是：

1. `network` / `process` 類規則在 AppArmor 路徑下為何失效
2. `torch.load` / `pickle` 類模型載入再補更多變種
3. `download-and-exec` 鏈是否能透過更嚴格的 process/network 規則補起來
