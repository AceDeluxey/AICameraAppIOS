# EfficientDet Core ML 模型契约

> 目标模型资源名：`EfficientDetLite2.mlpackage`（Xcode 构建后为 `EfficientDetLite2.mlmodelc`）

## 转换源

- 转换必须从 TensorFlow SavedModel、Keras 或受支持的 PyTorch 模型开始，不能把现有 `.tflite` 文件直接传给 `coremltools.convert()`。
- 首选 TensorFlow 发布的 EfficientDet Lite2 Detection TensorFlow 2 模型，并先确认它与 Android TFLite 模型的权重、输出和许可证关系。
- 当前 Android TFLite 模型不提交到 iOS 仓库；转换产物也须在商业复用确认和大文件方案确定后再提交。

## iOS 运行时接口

| 名称 | 类型 | 形状/约束 |
| --- | --- | --- |
| `image` | Image (RGB) | 448×448 |
| `locations` | MultiArray Float | `[1,25,4]`，顺序 `y1,x1,y2,x2` |
| `classes` | MultiArray Float | `[1,25]`，COCO 0-based |
| `scores` | MultiArray Float | `[1,25]` |
| `num_detections` | MultiArray Float | `[1]` |

`CoreMLEfficientDetDetector` 在加载时校验上述接口，不符合时立即报错，避免运行中静默错用模型。

## 输入与验证

- 相机帧按 Android 行为直接拉伸至 448×448，不做 letterbox。
- Core Image 输出 32BGRA PixelBuffer，Core ML 图像输入声明负责 RGB 通道解释。
- 首次模型转换必须在固定验证集上逐样本比较 Android 与 iOS 的原始四个输出，不能只比较最终框。
- Linux 可以生成和检查 `.mlpackage` 结构；实际预测校验、编译 `.mlmodelc` 和性能测试必须在 macOS/Xcode 及真机完成。
