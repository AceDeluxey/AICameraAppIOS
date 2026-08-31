# Mac 构建、签名与真机安装

## 前置条件

- 一台能运行当前 Xcode 的 Mac。
- Xcode 及其 iOS Simulator Runtime。
- Apple ID；真机长期测试和 TestFlight 建议使用 Apple Developer Program 账号。
- 一台开启“开发者模式”的测试 iPhone，首次连接时在手机上信任此 Mac。

## 生成并打开工程

在 Mac 终端进入仓库后执行：

```bash
brew install xcodegen swiftformat swiftlint
xcodegen generate
open AICameraApp.xcodeproj
```

`AICameraApp.xcodeproj` 是生成文件，不提交 Git；工程结构以 `project.yml` 为准。

## 本地检查

```bash
swiftformat Sources Tests UITests --lint
swiftlint lint --strict
xcodegen generate
xcodebuild \
  -project AICameraApp.xcodeproj \
  -scheme AICameraApp \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

CI 使用同一套生成和检查流程。若 CI 与本机结果不同，先核对 Xcode、XcodeGen、SwiftFormat 和 SwiftLint 版本。

## 签名与安装到 iPhone

1. 在 Xcode 打开 `AICameraApp` Target 的 Signing & Capabilities。
2. 勾选 Automatically manage signing，选择 Owner 的开发团队。
3. 确认 Bundle ID `com.acedeluxey.aicamera` 在该团队下可用；若已占用，先更新 `project.yml` 再重新生成工程。
4. 选择已连接的 iPhone 作为运行设备，执行 Run。
5. 首次启动允许相机权限，确认能看到后置相机预览。

不得把证书、私钥、Provisioning Profile、Apple ID 密码或会话 Token 提交到仓库或普通日志。

## M0 真机验收

- App 可安装、启动并按需申请相机权限。
- 授权后显示后置相机预览；拒绝后显示明确提示。
- 切换后台再回前台可以恢复预览，不崩溃。
- 连续预览 10 分钟无崩溃或持续内存增长。
- 记录 Mac 型号、macOS、Xcode、iPhone 型号和 iOS 版本，回填 `docs/TASKLIST.md`。
