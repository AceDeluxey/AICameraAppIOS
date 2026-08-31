# AICameraApp iOS

面向观鸟与手机接望远镜用户的 iPhone AI 相机。核心体验是实时发现鸟、持续追踪鸟体/鸟眼、驱动相机对焦，并在长焦场景下提高画面稳定性和出片率。

当前阶段：产品定义与真机技术验证。

- 产品需求：[docs/PRD.md](docs/PRD.md)
- 开发任务：[docs/TASKLIST.md](docs/TASKLIST.md)
- 开发协作规则：[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)
- Mac 构建与真机安装：[docs/MAC_SETUP.md](docs/MAC_SETUP.md)
- Android 原始压缩包：`/home/ubuntu/birdCamera/AICameraApp.rar`（只读参考，不直接修改或执行）
- Android 已解压工程：`/home/ubuntu/AICameraApp`（功能、交互、视觉和模型迁移的对照基线）

## 首版原则

1. 优先提高“拍到且拍清”的概率，不把鸟种百科作为主卖点。
2. 与 Android 版保持品牌、布局和操作逻辑一致；遵循 iOS 权限、相册和相机交互习惯。
3. 所有相机能力以真机动态探测结果为准，不按机型名称硬编码。
4. 先验证识别、追踪对焦和长焦防抖，再扩展专业参数与鸟种识别。

## 当前工程基线

- 应用名暂定 `AICameraApp`，Bundle ID 暂定 `com.acedeluxey.aicamera`，最低版本暂定 iOS 17。
- 使用 XcodeGen 维护 `project.yml`，`AICameraApp.xcodeproj` 在 Mac 上生成，不提交生成文件。
- 当前包含 SwiftUI 入口、AVFoundation 后置相机预览、七个模块边界、单元/UI 测试 Target、隐私清单和已通过的 macOS CI。
- M1.1 已加入运行时相机能力探测和 Debug 报告入口，可列出物理/虚拟镜头、格式、帧率、防抖、对焦、曝光和变焦能力。
- Android 模型和数据尚未复制，等待商业复用授权与模型仓库方案确认。
