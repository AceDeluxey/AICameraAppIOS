# M1.2 TFLite 备选路线

## 结论

Android 的 EfficientDet Lite2 `.tflite` 可作为 iOS 首版备选推理路线，避免等待同源 SavedModel 后才能验证检测闭环。仓库已实现不绑定模型资产的 `TFLiteEfficientDetDetector`：

- 加载时严格校验 `[1,448,448,3] uint8 RGB` 输入；
- 严格校验四个 Float32 输出及 Android 使用的 `[1,25,*]` 形状；
- 相机帧直接拉伸到 448×448 并转换为 RGB，不使用 letterbox；
- 复用现有 bird/cat 阈值、NMS 和单主目标后处理；
- 输出数量或字节数异常时立即失败，不将损坏结果传入对焦链路。

## iOS 运行时接入

Google 当前官方 Swift Interpreter 由 CocoaPods 的 `TensorFlowLiteSwift` 提供。代码内已提供条件编译的 `TensorFlowLiteEfficientDetRuntime`；未安装该模块时，Core ML 路线和普通 CI 不受影响。

正式接入前需在 Mac 分支验证 CocoaPods/XcodeGen 工作区流程，随后才可启用：

```ruby
pod 'TensorFlowLiteSwift'
```

模型文件仍不提交。只有确认 Android 模型、标签和权重的 iOS 复用与商业分发权限后，才允许将其通过确定的大文件方案加入 App。

## 待验收

1. Mac 上安装运行时并编译条件分支，核对四个张量的实际顺序、类型和形状。
2. 用固定图片逐样本比较 Android 与 iOS 原始四输出，要求数值一致或记录允许误差。
3. 真机分别测 CPU 与 Metal delegate 的延迟、内存、功耗及连续运行稳定性。
4. 与 Core ML 路线完成准确率、性能、包体和维护成本对比后再定首版方案。
