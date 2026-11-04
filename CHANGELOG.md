# Changelog

本文件记录**金花助手 (Jinhua Assistant)** 的所有重要版本变更。

格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 规范，版本号管理遵循 [语义化版本 2.0.0 (SemVer)](https://semver.org/lang/zh-CN/) 及项目确立的三阶段发布流转规范（`Pre -> RC -> Release`）。

## [Unreleased]

## [2.2.0-pre1] - 2026-11-04

本版本为 `v2.2.0` 开发预览版（Preview 1），重点建立强智教务解析层离线自动化测试基准、加固内嵌 WebView 白名单与执行隔离，并消除加密异常日志中的敏感数据暴露面。

### Added
- 新增根目录 `parser_test/` 测试套件，内建 6 组完全合成脱敏的 DOM Fixtures（覆盖双容器过滤、二维码节点剥离、4 节连排、表尾大跨度备注行阻断、五级制/二级制成绩折算、无座位号考试日程与统一身份认证登录负例）。
- 基于 Node 24 原生 `node:test` + JSDOM 实现 13 项强智核心 DOM 解析用例全自动化断言。
- GitHub Actions CI/CD 工作流（`.github/workflows/ci_cd.yml`）在代码质量门禁（`quality_check`）中接入 Node 24 环境、npm 依赖缓存与 `node --test` 回归测试。
- 新增 `WebViewLoginScreen.isAllowedUrl` 专属安全单测（`test/webview_security_test.dart`），全方位覆盖空 Host、钓鱼仿冒域名、明文 HTTP 协议降级等边界场景。

### Security
- 修复 `WebViewLoginScreen.isAllowedUrl` 中空 Host 被意外放行的逻辑漏洞，严格限定仅放行有效校内 HTTPS 域名及内核空白页。
- 增强 Windows 端 WebView 导航拦截，触发非白名单拦截时先调用 `_winController.stop()` 立即终止当前加载。
- 建立统一的 `_safeExecuteScript` 注入门禁，在执行任何教务提取脚本前强制校验页面白名单，非校内页面一律禁止注入脚本。
- 脱敏 `AppCryptoService.getMasterKey` 与 `AppCryptoService.decrypt` 中的异常提示文本，移除私钥明文与加密载荷的字符串插值。

### Changed
- 生产解析脚本 `qiangzhi_parser.js` 引入跨环境文本提取函数 `getNodeText`，平滑兼容 Node JSDOM 与双端 WebView 浏览器环境。
- 脱敏 `test/schedule_dedup_test.dart` 中的单测教师姓名数据，统一对齐为教学化名。

## [2.1.2] - 2026-11-03

本版本只调整工程与发布流程，App 功能与数据处理行为没有变化。

### Added
- 新增仓库根目录 `CHANGELOG.md`，按 Keep a Changelog 1.1.0 规范归档各版本变更记录。
- GitHub Release 正文改为自动取自 `CHANGELOG.md` 中对应版本的段落；如果缺少该版本段落，发布流程会直接失败。
- CI 在打 tag 时校验 tag 版本号与 `pubspec.yaml` 中的版本号一致，不一致就中止构建。
- 新增单元测试，校验应用内显示的版本号（`LegalService.appVersion`）与 `pubspec.yaml` 保持一致。

### Changed
- 更新 `xaut_app/pubspec.yaml` 的 `description` 字段，移除脚手架默认占位符，对齐项目定位与非官方声明。
- CI 固定 Flutter 版本为 `3.47.8`，与本地开发环境一致。
- CI 运行环境由 `ubuntu-latest` / `windows-latest` 固定为 `ubuntu-24.04` / `windows-2025`。
- CI 依赖的 GitHub Actions 升级到 Node 24 运行时版本（`checkout@v5`、`upload-artifact@v7`、`download-artifact@v8`、`action-gh-release@v3`），消除 Node 20 弃用告警。
- 导出的 `.ics` 文件中 `PRODID` 的版本号改为直接引用应用版本常量，不再需要每次发版手动修改。
- 同步更新 `README.md` 中的 Flutter/Dart SDK 最低版本要求（Flutter >= 3.47.0 / Dart >= 3.13.7）与工程目录树说明。

## [2.1.1] - 2026-11-02

### Added
- 在 `THIRD_PARTY_NOTICES.md` 与内置开源致谢文档中新增第 4 节，完整公示 10 项纯本地 Flutter/Dart 开源依赖组件及其许可证类别（MIT / BSD-3-Clause）。
- 在 `README.md` 确立并归档 `Pre -> RC -> Official Release` 三阶段版本发布流转规范。

### Changed
- 更新《隐私政策》与《用户服务协议》，补充 AES-256-GCM 硬件级落盘加密、撤回同意密码学粉碎及 RFC 5545 系统日历（`.ics`）导出范围说明（明确课表与考试支持 `.ics` 导出，成绩仅限应用内查看与核对）。
- 更新 `SECURITY.md` 安全维护支持矩阵，将主干支持对齐至 `v2.1.x`。
- 加固 GitHub Actions CI/CD 发布工作流（`.github/workflows/ci_cd.yml`），根据 Tag 名称动态设置 `prerelease` 与 `make_latest`，防止预发布版本覆盖正式版 `Latest` 标识。

### Fixed
- 修正 `WebViewLoginScreen` 考试日程同步完成弹窗中的遗留文案，移除不实“座位号”字样，如实提示“已自动提取考试时间与考场教室”，并同步清理单测模拟数据。
- 修正历史 Release 下载说明中的 Windows 可执行文件名描述，统一对齐为实际产物 `jinhua_assistant.exe`。

## [2.1.0] - 2026-11-02

### Added
- **RFC 5545 标准系统日历导出（`.ics`）**：
  - 支持将整学期课程表（按活跃教学周展开）与期末考试安排（校区 + 考场教室，不含座位号）导出为 `.ics` 日历文件；
  - 内置标准 `Asia/Shanghai`（UTC+8）时区定义、确定性稳定业务 `UID`、`SEQUENCE:0` 与 `LAST-MODIFIED` 属性；
  - 实现严格的 RFC 5545 §3.1 75 字节 UTF-8 安全折行机制，兼容苹果日历、各大 Android 厂商系统日历、Outlook 与 Google 日历；
  - 支持自定义课前（15 分钟 / 30 分钟 / 1 小时）与考前（2 小时 / 1 天）`VALARM` 提醒，支持系统分享、保存本地文件与复制源码。

### Changed
- 精确收窄《隐私政策》第七条关于复制权与可携带权的表述，如实阐明导出文件为明文且脱离应用沙盒保护，撤回同意或卸载应用不会自动删除外部副本；合规协议版本升级至 `2026-11-02.v6`。

### Security
- **全量学业数据 AES-256-GCM 硬件级落盘加密（Encryption at Rest）**：
  - 课表日程、成绩与 GPA 汇总、期末考试安排全部采用 AEAD AES-256-GCM 信封加密（`ENC:v1:<Nonce>:<CiphertextWithTag>`），支持旧版明文缓存无感透明升级；
  - 加密根密钥通过 `flutter_secure_storage` 托管于 Android Hardware Keystore 与 Windows DPAPI / 凭据管理器；
  - 引入 Single-Flight 单飞锁消除冷启动多模块并发初始化主密钥的竞态条件，区分硬件读取异常与首次安装空值以防误覆盖主密钥；
  - 撤回知情同意时执行 `destroyMasterKey()` 密码学粉碎（Crypto-Shredding），彻底销毁主密钥。

## [2.0.3] - 2026-11-01

### Added
- 在《隐私政策》中补充个人信息可携带权条款说明。

### Fixed
- 修正文档中 Android APK 包体积的事实描述偏差（约 19.4 MB）。
- 撤回同意清理缓存时保留应用缓存根目录本身，仅清空目录内部子项，避免部分系统环境下根目录重建异常。

### Security
- 强化内嵌 WebView 导航安全拦截，强制校验 `HTTPS` 协议与 `xaut.edu.cn` 校内合法域名白名单。

## [2.0.2] - 2026-11-01

### Changed
- 升级合规协议版本号至 `2026-11-01.v4`，确保隐私条款更新后自动触发存量用户重新确认。

### Fixed
- 在 Android Gradle 打包配置中显式排除第三方 AAR 携带的冗余非 arm64 原生库（`armeabi-v7a`、`x86`、`x86_64`），保持纯 `arm64-v8a` 产物精简。

### Security
- 在 Android 原生侧增加 `WebStorage.getInstance().deleteAllData()` 与 Cookie 深度清理通道，确保撤回授权时彻底清除 DOM Storage 会话残留。

## [2.0.1] - 2026-10-31

### Fixed
- 修复 `LicensePage` 开源许可证页面展示的应用版本号未与 `LegalService.appVersion` 同步的问题。

## [2.0.0.beta3] - 2026-10-31

### Added
- 完善多端知情同意撤回时的本地缓存、数据库与 Cookie 清理机制，细化《隐私政策》中的用户法定权利章节。

### Changed
- Android Release 构建限定单架构 `arm64-v8a`，并显式启用 v1 / v2 / v3 全签名方案。

### Security
- 在 GitHub Actions 发布流水线中集成 `apksigner` 签名校验与官方发布证书 SHA-256 指纹强制核验，阻断 Debug 证书或未授权签名包发布。

## [2.0.0.pre1] - 2026-10-31

### Added
- 初始开源版本发布（GPL-3.0 许可证），支持 Android 与 Windows 双端原生运行。
- 实现强智教务系统内嵌官方网页登录与一键并发同步（课表、成绩、考试安排）及当前教学周自动识别校准。
- 实现课表「仅本周 / 所有周」视图切换、同节次冲突课程叠层展示、左右滑动翻周及固定 6 大节 / 13 小节时间轴。
- 实现分学期 / 累计动态加权平均分与 GPA 演算（兼容五级制与二级制成绩）及考试倒计时智能排序。
- 内置离线《用户服务协议》《隐私政策》《免责声明》与首次启动强制阅读知情同意门禁（`LegalGateScreen`）。

[Unreleased]: https://github.com/korty258/xaut-assistant/compare/v2.2.0-pre1...HEAD
[2.2.0-pre1]: https://github.com/korty258/xaut-assistant/compare/v2.1.2...v2.2.0-pre1
[2.1.2]: https://github.com/korty258/xaut-assistant/compare/v2.1.1...v2.1.2
[2.1.1]: https://github.com/korty258/xaut-assistant/compare/v2.1.0...v2.1.1
[2.1.0]: https://github.com/korty258/xaut-assistant/compare/v2.0.3...v2.1.0
[2.0.3]: https://github.com/korty258/xaut-assistant/compare/v2.0.2...v2.0.3
[2.0.2]: https://github.com/korty258/xaut-assistant/compare/v2.0.1...v2.0.2
[2.0.1]: https://github.com/korty258/xaut-assistant/compare/v2.0.0.beta3...v2.0.1
[2.0.0.beta3]: https://github.com/korty258/xaut-assistant/compare/v2.0.0.pre1...v2.0.0.beta3
[2.0.0.pre1]: https://github.com/korty258/xaut-assistant/releases/tag/v2.0.0.pre1
