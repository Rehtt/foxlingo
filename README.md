# FoxLingo · 狐译

基于 Flutter 的 Android 屏幕翻译应用。切换到其他应用后，点击悬浮球截取当前屏幕，识别文字并将译文覆盖到对应位置。

当前处于 MVP 阶段，仅支持 Android。翻译结果显示在本次截屏的静态画面上；关闭结果后可继续操作原应用，再次点击悬浮球获取新的翻译。

## 功能

- 可拖动悬浮球，手动触发截屏与翻译，支持取消任务和停止会话。
- 两种识别与翻译方式：设备端 OCR + 文本翻译，或视觉 LLM 一次完成识别、翻译和文字定位。
- 设备端 OCR 支持拉丁文、中文、日文、韩文。
- 文本翻译支持 OpenAI 兼容接口、Google 翻译和微软翻译。
- 可配置目标语言、模型与文本翻译提示词，并在设置中测试连接。
- 启动自动检测 GitHub 稳定版更新，设置页支持手动检查、查看更新说明并打开下载页。
- 中文 / 英文界面，浅色 / 深色主题及跟随系统模式。

## 使用方法

1. 安装并打开应用，进入「设置 → 翻译设置」。
2. 选择「图片翻译方式」，按下方说明配置服务、目标语言及 OCR 识别文字，保存设置。可先点击「测试」或「测试图片翻译」检查配置。
3. 返回首页，点击「开始翻译」，按系统提示授予悬浮窗和本次会话的录屏权限。
4. 切换到需要翻译的应用，点击悬浮球，等待译文显示。
5. 点击「关闭」返回悬浮球；需要结束时，在首页点击「停止翻译」，或通过截屏服务通知停止会话。

### 应用更新

启动主应用时会检查 `Rehtt/foxlingo` 的最新稳定版 Release，也可在「设置 → 检查更新」手动检查，入口显示安装包的真实版本。更新说明按界面语言显示。点击「稍后」后，该版本不再自动提示，手动检查仍可查看；返回或点击弹窗外部关闭不会忽略版本。点击「下载」会通过外部浏览器打开发布页，请选择适合设备架构的签名 APK（不要选 `-unsigned`）。应用不自动下载或安装 APK。

### 设备端 OCR + 文本翻译

在「图片翻译方式」中选择「设备端 OCR + 文本翻译」，再选择与屏幕文字匹配的「OCR 识别文字」和文本翻译服务。

| 翻译服务 | 必填配置 |
| --- | --- |
| LLM（OpenAI 兼容） | API 地址、API Key、模型；地址和模型有默认值 |
| Google 翻译 | Google Cloud API Key |
| 微软翻译 | Azure 订阅密钥、Azure 区域 |

LLM 客户端会在 API 地址后追加 `/chat/completions`，请填写服务的基础地址，避免重复填写该路径。文本翻译的 System 提示词支持 `{targetLanguage}` 占位符。

### 视觉 LLM

在「图片翻译方式」中选择「视觉 LLM（识别并翻译）」，配置图片翻译的 API 地址、API Key 和模型。接口需要兼容应用使用的 Chat Completions 图片输入格式，模型需要支持图片理解。

图片翻译的地址、密钥和模型分别留空时，会沿用对应的文本 LLM 配置。此模式无需配置 OCR 识别文字。

应用不附带翻译服务密钥，需要自行准备。两种模式的翻译请求都需要联网，调用额度和费用由所配置的服务决定。

## 权限与数据处理

| 权限 | 用途 |
| --- | --- |
| 悬浮窗 | 在其他应用上方显示悬浮球和翻译结果 |
| 录屏授权（MediaProjection） | 在本次会话中截取屏幕，启动会话时通过系统授权 |
| 前台服务与通知 | 维持截屏 / 悬浮窗服务，并提供会话状态与停止入口 |
| 网络 | 请求所配置的翻译服务及 GitHub 更新接口 |

Android 13 及以上会请求通知权限；拒绝通知权限不会被视为拒绝录屏授权。

- **OCR 模式**：图片在设备端识别，识别出的文字发送至所选翻译服务。
- **视觉 LLM 模式**：截图上传至所配置的模型接口进行识别和翻译。
- 启动及手动检查更新会请求 `api.github.com/repos/Rehtt/foxlingo/releases/latest`，不发送截图、翻译文本或 API Key。自动检查失败不提示；手动检查会显示失败信息。忽略的更新版本使用本机安全存储保存。
- 翻译配置与 API Key 使用 `flutter_secure_storage` 在本机保存。录屏授权令牌仅保存在内存中。

## 本地开发

### 环境准备

- Flutter SDK，所附 Dart 版本须满足 `pubspec.yaml` 中的 `^3.12.0` 约束。
- Android SDK、JDK 17，以及开启 USB 调试的 Android 设备或 Android 模拟器。
- 首次构建需要下载 Flutter / Android 依赖。

在项目根目录执行：

```sh
flutter doctor
flutter pub get
flutter gen-l10n
flutter devices
flutter run -d <设备ID>
```

仓库中的 `make run-gs` 使用特定的 ADB 服务端口 `15037`，普通设备调试使用上面的 `flutter run` 即可。

### 检查与调试构建

```sh
flutter analyze
flutter test
flutter build apk --debug
```

调试安装包位于 `build/app/outputs/flutter-apk/app-debug.apk`。

### 发布构建

Release 构建必须配置独立的发布签名。准备签名密钥库后，在本机创建 `android/key.properties`：

```properties
storeFile=/absolute/path/to/upload-keystore.jks
storePassword=YOUR_STORE_PASSWORD
keyAlias=YOUR_KEY_ALIAS
keyPassword=YOUR_KEY_PASSWORD
```

`storeFile` 建议使用绝对路径；相对路径以 `android/app` 为基准。也可通过环境变量 `ANDROID_STORE_FILE`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD` 提供配置，适用于 CI。

```sh
flutter build apk --release
# 如需 Android App Bundle：
flutter build appbundle --release
```

输出分别位于 `build/app/outputs/flutter-apk/app-release.apk` 和 `build/app/outputs/bundle/release/app-release.aab`。未提供完整签名配置时，构建会报错。

`android/key.properties` 已被 Git 忽略；请勿提交真实 API Key、签名密码或密钥库文件。

### GitHub Tag 自动发布

推送符合 `vMAJOR.MINOR.PATCH` 的 Tag（例如 `v0.2.0`）会触发 GitHub Actions 发布。Tag 中的版本号会写入 APK 的 `versionName`，该次 Actions 运行编号会作为 `versionCode`。发布 Workflow 使用 Flutter 3.44.0 和 Java 17。

仓库需要配置以下 GitHub Actions Secrets：

| Secret | 用途 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Android `.jks` / `.keystore` 文件的 Base64 内容 |
| `ANDROID_KEYSTORE_PASSWORD` | 密钥库密码 |
| `ANDROID_KEY_ALIAS` | 签名别名 |
| `ANDROID_KEY_PASSWORD` | 签名密码 |

每次发布会创建或更新标题为 `FoxLingo <版本号>` 的 GitHub Release，并上传以下 6 个 APK：

- 签名版：`foxlingo-<版本号>-arm64-v8a.apk`、`foxlingo-<版本号>-armeabi-v7a.apk`、`foxlingo-<版本号>-x86_64.apk`
- 无签名版：对应文件名追加 `-unsigned`，例如 `foxlingo-<版本号>-arm64-v8a-unsigned.apk`

签名版适合直接安装或分发；无签名版适合需要自行签名的下游构建流程。`unsignedRelease` 变体继承 Release 的编译、资源及 ProGuard 配置，但关闭该变体的代码 / 资源压缩以兼容 Flutter 插件，并且不会读取或要求发布签名。

## 项目结构

```text
lib/
  client/          # OCR、文本翻译与视觉模型客户端
  controllers/     # 屏幕翻译会话与任务生命周期
  models/          # 翻译结果、OCR 与会话数据模型
  pages/           # 首页与设置页
  platform/        # 截屏、悬浮窗与原生通信
  widgets/         # 悬浮球、译文覆盖层与进度组件
  utils/           # 设置存储及响应处理
  l10n/            # 中英文界面资源
android/app/src/main/kotlin/com/rehtt/foxlingo/
                   # Android 截屏前台服务与 Flutter 通信桥
test/              # 单元测试与组件测试
```

实现细节、会话生命周期与验证记录见 [PROJECT.md](PROJECT.md)。

## 当前限制与验证状态

- 当前为手动、单帧翻译，尚不支持区域选择、连续翻译、翻译历史、结果导出或自动重启。
- 翻译结果是静态截图覆盖层，无法在结果画面中直接操作底下的应用。
- 受保护内容、锁屏、屏幕旋转与不同 Android 版本的系统行为仍需真机验证。
- 根据 [PROJECT.md](PROJECT.md) 中 2026-09-10 的记录，71 项 Flutter 测试、静态分析、Kotlin 调试编译和 Debug APK 构建已通过。尚未完成 Android 真机 / 模拟器验收，也未验证真实翻译服务请求。

反馈问题时，请附上 Android 版本、设备型号、翻译模式、复现步骤与脱敏日志，方便定位问题。

## 许可证

本项目采用 [MIT License](LICENSE) 开源协议。
