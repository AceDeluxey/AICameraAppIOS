# M1.2 固定验证集与跨端输出对比

验证集用于同图、同权重比较 Android TFLite、iOS TFLite 与 iOS Core ML。图片不提交到仓库；仅在授权与隐私确认后放入本地验证集目录。

## 验证集清单

`manifest.json` 使用以下格式，图片路径相对清单目录，`sha256` 用于防止样本被静默替换：

```json
{
  "schema_version": 1,
  "samples": [
    {
      "id": "bird-small-001",
      "image": "images/bird-small-001.jpg",
      "sha256": "<64 位 SHA-256>",
      "categories": ["bird", "small_target", "occluded", "complex_background"]
    },
    {
      "id": "negative-001",
      "image": "images/negative-001.jpg",
      "sha256": "<64 位 SHA-256>",
      "categories": ["no_bird", "backlit", "motion"]
    }
  ]
}
```

全套清单必须覆盖 `bird`、`no_bird`、`small_target`、`occluded`、`motion`、`backlit`、`complex_background`；每个样本必须且只能属于 `bird`/`no_bird` 之一。正式基线建议每类至少 20 张，并保留原始图片授权和来源记录，来源记录不得含个人敏感信息。

校验清单和图片：

```bash
python3 tools/compare_detection_outputs.py /path/to/manifest.json --check-files
```

## 运行输出

Android 和 iOS 各输出一份 JSON。`selected_detection` 是应用后处理后唯一主目标；无目标时为 `null`。框固定为转正图像上的归一化 `[y1,x1,y2,x2]`。

```json
{
  "schema_version": 1,
  "runtime": "android_tflite",
  "source_model_sha256": "6fd32c84ab1eb0f7e7f3a7a20a20d7df1530daa8378728f7c79571096286bd52",
  "samples": [
    {
      "id": "bird-small-001",
      "latency_ms": 82.4,
      "selected_detection": {
        "class_id": 14,
        "score": 0.72,
        "box": [0.1, 0.2, 0.7, 0.8]
      }
    }
  ]
}
```

`source_model_sha256` 表示权重来源；两份输出不一致时工具拒绝比较，避免把不同权重误判为平台差异。

## 对比与门槛

```bash
python3 tools/compare_detection_outputs.py \
  /path/to/manifest.json \
  /path/to/android.json \
  /path/to/ios.json \
  --output /path/to/report.json
```

报告同时给出两端推理耗时的平均值、P95 和最大值。默认数值一致性门槛：有无目标一致率不低于 95%，同现目标类别完全一致，平均 IoU 不低于 0.90，平均置信度绝对差不高于 0.05。工具退出码：`0` 通过、`1` 输入无效、`2` 指标未通过。门槛可通过命令行参数调整，但 M1 决策报告必须记录调整理由。

该工具比较数值一致性，不替代准确率标注、真机端到端延迟、内存、功耗和温度测试。
