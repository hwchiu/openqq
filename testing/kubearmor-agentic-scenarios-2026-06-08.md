# KubeArmor Agentic Scenario Expansion (2026-06-08)

這份報告整理 `k3s-kubearmor-runc` 在 2026-06-08 進一步擴充的 agentic / AI-like scenario 驗證結果。

## 為什麼擴充

原本只有：

- `service account token read`

這不足以解釋 KubeArmor 在 agentic 場景下到底擅長什麼、不擅長什麼。

所以這次把場景拆成：

1. `secret-read`
2. `sensitive-file-read`
3. `process-exec`
4. `network-egress`
5. `payload-staging`
6. `python subprocess shell escape`
7. `pip install`
8. `pip install + import`
9. `pickle-rce`
10. `download-and-exec`

## 結果摘要

| Scenario | Result | 解讀 |
| --- | --- | --- |
| Service account token read | PASS | secret guardrail 成立 |
| Sensitive file read (`/etc/nginx/nginx.conf`) | PASS | file read guardrail 成立 |
| Process execution (`/usr/bin/sleep`) | FAIL | process rule 目前未如預期生效 |
| Curl TCP egress | FAIL | network rule 目前未如預期生效 |
| Python secret read | PASS | `ModelArmor-style` secret guardrail 成立 |
| Python subprocess shell escape | FAIL | `/bin/sh` deny 已入 profile，但實測未擋下 |
| Python HTTP egress | FAIL | `deny network tcp` 已入 profile，但實測未擋下 |
| Payload staging to `/tmp` | DEGRADED | 可下載並落地到 `/tmp` |
| `pip install` to `/tmp` | DEGRADED | 套件可下載並安裝到暫存目錄 |
| `pip install + import` | DEGRADED | agent 可完成自我擴展並立即載入新模組 |
| `pickle`-driven code execution | FAIL | 反序列化可直接帶出 `os.system()` |
| in-cluster download-and-exec | FAIL | 下載 script 後可直接透過 `/bin/sh` 執行 |

## KubeArmor demo workload

### PASS

1. service account token read
   - [kubearmor-hardening-2026-06-08.md](/Users/hwchiu/hwchiu/openqq/testing/kubearmor-hardening-2026-06-08.md)

2. sensitive file read
   - [file-block result](/Users/hwchiu/hwchiu/openqq/generated/kubearmor-file/verify.stderr)

### FAIL

1. process execution
   - [process-block script](/Users/hwchiu/hwchiu/openqq/scripts/tests/kubearmor-process-block.sh)
   - 實測：`/usr/bin/sleep` 仍可執行

2. network egress
   - [network-block script](/Users/hwchiu/hwchiu/openqq/scripts/tests/kubearmor-network-block.sh)
   - 實測：`curl http://example.com` 仍回 `200 OK`

## ModelArmor-style lab

詳細結果在：

- [modelarmor-lab-validation-2026-06-08.md](/Users/hwchiu/hwchiu/openqq/testing/modelarmor-lab-validation-2026-06-08.md)

### PASS

1. Python secret read
   - [secret-read.json](/Users/hwchiu/hwchiu/openqq/testing/raw/modelarmor-lab-2026-06-08/secret-read.json)

### FAIL / DEGRADED

1. Python subprocess shell escape
   - [shell-escape.json](/Users/hwchiu/hwchiu/openqq/testing/raw/modelarmor-lab-2026-06-08/shell-escape.json)

2. Python HTTP egress
   - [python-egress.json](/Users/hwchiu/hwchiu/openqq/testing/raw/modelarmor-lab-2026-06-08/python-egress.json)

3. Payload staging to `/tmp`
   - [payload-stage.json](/Users/hwchiu/hwchiu/openqq/testing/raw/modelarmor-lab-2026-06-08/payload-stage.json)

4. `pip install` 到 `/tmp`
   - [pip-install.json](/Users/hwchiu/hwchiu/openqq/testing/raw/modelarmor-lab-2026-06-08/pip-install.json)

5. `pip install + import`
   - [pip-import.json](/Users/hwchiu/hwchiu/openqq/testing/raw/modelarmor-lab-2026-06-08/pip-import.json)

6. `pickle`-driven code execution
   - [pickle-rce.json](/Users/hwchiu/hwchiu/openqq/testing/raw/modelarmor-lab-2026-06-08/pickle-rce.json)

7. in-cluster download-and-exec
   - [download-exec.json](/Users/hwchiu/hwchiu/openqq/testing/raw/modelarmor-lab-2026-06-08/download-exec.json)

## 重要技術發現

這次最重要的不是單純的 PASS/FAIL，而是：

### 1. File / secret 類規則比較穩

至少在目前 `k3s + containerd + AppArmor` 路徑下：

- secret read
- sensitive file read

都能穩定被擋下。

### 2. Process / network 類規則沒有同樣成熟

最關鍵證據是：

- [apparmor-profile.txt](/Users/hwchiu/hwchiu/openqq/testing/raw/modelarmor-lab-2026-06-08/apparmor-profile.txt)

它裡面已經有：

- `deny /bin/sh x`
- `deny network tcp`

但 runtime 實測依然出現：

- Python subprocess shell escape 成功
- Python HTTP egress 成功

這表示：

- 問題不是「policy object 沒建立」
- 也不是「profile 根本沒生成」
- 而是目前這條 enforcement 路徑對某些行為類型，和預期有差距

## 對 agentic 場景的意義

如果你把這條線拿來保護 agent / model / tool-use workload，目前比較可靠的是：

1. 防 secret read
2. 防特定敏感檔案讀取

目前還不能高信心宣稱：

1. 防 shell escape
2. 防 Python 對外 callback
3. 防 payload download-and-stage
4. 防 `pip install` 這種 agent self-extension
5. 防 `pip install + import` 這種 agent 自我擴展後立即啟用
6. 防 `pickle` / untrusted model load 導致的 code execution
7. 防 in-cluster download-and-exec

## 下一步

最值得繼續追的不是更多產品名稱，而是：

1. 釐清 AppArmor path 下 process/network 為何失效
2. 把 `pickle` / `torch.load` / `subprocess` / `download-and-exec` 場景繼續補齊
3. 再拿這些同一批 scenario 去對照 OpenShell / gVisor / Istio 疊加後的差異
