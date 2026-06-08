# Latest Matrix Results

這個目錄預留給本地 runner 的最新輸出。

實際流程：

1. `./scripts/run-comparison-matrix-tests.sh`
2. 產生 `testing/results/latest/<stack>/<test>.json`
3. 若要發佈到 GitHub Pages，使用：
   `PUBLISH_RESULTS=true ./scripts/run-comparison-matrix-tests.sh`
4. 這會更新 `docs/data/comparison-matrix.json`

repo 預設不提交本地最新結果，避免把尚未重跑的 `pending` 狀態誤當成正式發佈資料。
