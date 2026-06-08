# Comparison Matrix

這個目錄定義四套環境的共用比較語言。

- `catalog.json`: stack 與 test case 的正式定義
- `testing/results/latest/`: runner 產生的最新結果
- `docs/data/comparison-matrix.json`: GitHub Pages 讀取的發佈版本

## 執行方式

```bash
./scripts/run-comparison-matrix-tests.sh
```

如果要把最新結果同步到 GitHub Pages 資料檔：

```bash
PUBLISH_RESULTS=true ./scripts/run-comparison-matrix-tests.sh
```
