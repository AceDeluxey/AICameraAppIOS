# M1.2 Android 鸟体检测基线

> 记录日期：2026-08-31
> 参考工程：`/home/ubuntu/AICameraApp`

## 模型与标签

| 项目 | 值 |
| --- | --- |
| 模型 | `app/src/main/assets/efficientdet-lite2.tflite` |
| 模型大小 | 7,557,887 bytes |
| 模型 SHA-256 | `6fd32c84ab1eb0f7e7f3a7a20a20d7df1530daa8378728f7c79571096286bd52` |
| 标签 | `app/src/main/assets/labelmap_efficientdet.txt` |
| 标签数量 | 80 |
| 标签 SHA-256 | `bd17f1ee35d5f3c862a4894605855abbb9dda4b0621fdb0ac4c2c8c7bb7e730a` |
| 来源声明 | Android 注释记录为 TFHub `efficientdet/lite2/detection`，正式迁移前仍需补许可证与商业复用确认 |

模型文件暂不复制到 iOS 仓库，避免在授权和大文件管理方案确认前扩大分发范围。

## 输入

- 张量：`[1, 448, 448, 3]`，`uint8` RGB。
- Android 从 `YUV_420_888` 分析帧直接采样缩放到 448×448。
- 依据 `ImageProxy.rotationDegrees` 将 0°/90°/180°/270° 图像旋转转正。
- 当前实现是直接拉伸到正方形，没有 letterbox；iOS 对照测试必须保持相同几何行为。

## 输出与后处理

- `locations [1,25,4]`，顺序为 `y1,x1,y2,x2`，坐标裁剪到 0...1。
- `classes [1,25]`、`scores [1,25]`、`num_detections [1]`，均为 float。
- COCO 标签为 0-based：`bird=14`、`cat=15`。
- bird 阈值 0.10；cat 作为鸟的兼容阈值 0.30。
- NMS IoU 阈值 0.45，最终只保留最高可信的一个主目标。

## iOS 输入管线约束

- `AVCaptureVideoDataOutput` 使用独立串行队列，不占用主线程或相机会话队列。
- `alwaysDiscardsLateVideoFrames=true`，分析来不及时优先丢旧帧。
- 首版输入采用 32BGRA，模型适配层负责缩放、旋转及 RGB/量化转换。
- `BirdDetectionScheduler` 同时只允许一个推理任务，并支持最小帧间隔；新帧不得排队拖高延迟。

## 尚未完成

- 从 TFLite 转换并验证 Core ML 模型。
- iOS 已实现与 Android 参数一致的输出解析、bird/cat 双阈值、NMS、单主目标裁决和转正框逆旋转映射；待转换模型接入后做逐样本校验。
- iOS 已实现 Core ML 图像输入缩放、模型接口校验、推理输出读取与后处理适配；接口约定见 `COREML_MODEL_CONTRACT.md`。
- 接入 iOS ONNX Runtime/TFLite 的备选实测。
- TFLite 备选适配器、严格张量契约、RGB 输入和后处理复用已完成，接入说明见 `TFLITE_FALLBACK.md`；待 Mac 安装官方运行时并用现有模型验证。
- 固定验证集规范、完整性校验与 Android/iOS 逐样本输出对照工具已完成，见 `DETECTION_VALIDATION.md`；待取得有授权的图片并从两端导出真实结果。
- 真机统计端到端延迟、内存、功耗和温度。
