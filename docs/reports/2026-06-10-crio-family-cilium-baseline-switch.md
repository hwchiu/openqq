# CRI-O Family Cilium Baseline Switch - 2026-06-10

這份紀錄標記 `Decision Lab` 的正式比較基線更新：

- 舊模型：`K3s + CRI-O + Flannel workaround`
- 新模型：`K3s + CRI-O + no-flannel + Cilium`

這不是在否定先前的 recovery 或 failure 報告，而是把它們降級成 `historical baseline evidence`，不再直接作為目前官方推薦的正式依據。

## 為什麼要切換

先前 `plain CRI-O` 在兩條基線上遇到的 `bandwidth plugin panic`，後來證明可以透過 pinned flannel override 修正。這個 discovery 很重要，因為它說明第一次 failure 不是 solution 本質不支援。

但這也暴露另一個問題：

`Flannel workaround` 本身已經成為測試結果的一部分，甚至開始主導後續判讀。這會讓 repo 很難回答「哪個 sandbox solution 最適合」，因為讀者最後看到的會是「哪個 workaround 暫時把 CRI-O baseline 救起來」。

因此，CRI-O family 的官方比較基線現在改成：

1. `K3s` 以 `--flannel-backend=none` 啟動
2. `CRI-O` 作為 container runtime
3. `Cilium` 作為正式 CNI
4. 之後才安裝 candidate-specific components，例如 OpenShell、gVisor、KubeArmor

## 影響範圍

以下候選都受影響，必須在新基線上重跑：

- `K8s + CRI-O`
- `K8s + OpenShell + CRI-O`
- `K8s + gVisor`
- `K8s + OpenShell + gVisor`
- `K8s + CRI-O + KubeArmor`

## 舊結果怎麼處理

先前文件不刪除，保留為：

- 首次 failure observation
- recovery observation
- root-cause evidence

但它們現在都應被解讀成：

- `historical / superseded baseline`

而不是：

- `current official recommendation`

## 新的判讀順序

每個 CRI-O family 候選在兩條平台基線上，都要依序留下：

1. `Provision`
2. `Install / Bootstrap`
3. `Cilium Readiness`
4. `Baseline Readiness`
5. `Scenario Results`

任何一步失敗都要正式記錄：

- `cluster bootstrap failure`
- `cilium readiness failure`
- `solution bootstrap failure`
- `scenario execution failure`

## 下一步

這次變更後，最優先要補的不是更多結論，而是新的正式證據：

1. `plain CRI-O` 兩條基線的 Cilium bootstrap
2. `OpenShell + CRI-O` 在 Cilium 上的 controller / runtime verify
3. `gVisor` 在 Cilium 上的 RuntimeClass verify
4. `KubeArmor` 在 Cilium 上的 explicit-policy 驗證
5. `Istio` 與上述候選疊加後的 compatibility
