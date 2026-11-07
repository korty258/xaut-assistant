# Changelog

本文件记录**金花助手 (Jinhua Assistant)** 的所有重要版本变更。

格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 规范，版本号管理遵循 [语义化版本 2.0.0 (SemVer)](https://semver.org/lang/zh-CN/) 及项目确立的三阶段发布流转规范（`Pre -> RC -> Release`）。

## [Unreleased]

## [2.3.0-rc1] - 2026-11-07

本版本为 `v2.3.0` 发布候选版（Release Candidate 1），完成异步同步生命周期隔离、防抖与四态缓存语义加固、学期基准跳变确认保护、主密钥写后强一致校验、Windows 撤回授权冷启动补偿擦除、隐私政策 `v7` 对齐以及 CI `SHA256SUMS.txt` 校验清单集成。

### Changed
- **异步桥接请求生命周期隔离与精确路由**：
  - `WebViewPlatformAdapter` 与 `ParserService` 引入全局递增 `requestId` 路由机制，跨端消息分发严格按 `requestId` 校验挂起请求，超时与已取消任务的迟到响应直接丢弃，彻底消除跨请求数据污染。
  - 建立统一的任务总超时预算与 `window.__jinhuaAbortTask` 尽力而为取消钩子，在页面跳转、刷新或销毁时主动取消正在运行的任务；超时文案明确区分“停止等待（迟到响应丢弃）”，避免虚假承诺底层网络立即中止。
  - 彻底解耦 WebView 页面加载状态（`isLoadingNotifier`）与数据同步状态（`isSyncingNotifier`），底部操作栏与 AppBar 进度感知独立分流，消除页面重绘意外解锁按钮的竞态隐患。
- **一键全量同步数据源隔离 (`ParserService.buildSyncAllInjectionScript`)**：
  - 课表与全量成绩始终通过异步 Fetch 独立拉取默认数据源，严禁读取当前浏览页 `document`，避免用户在成绩页或课表页筛选无数据学期时导致误清空本地全部历史数据。

### Fixed
- **同步弹窗一键同步全部防抖自锁修复 (`WebViewSyncCoordinator`)**：
  - 修复用户在非业务功能页点击同步时，因智能提示弹窗过早记录时间戳导致弹窗内点击“一键同步全部”被 3 秒冷却自锁拦截的问题；冷却检测移至实际任务执行点。
- **空数据与异常/未登录本地缓存语义对齐**：
  - 严格按四态语义处理本地存储：当前学期无数据（`empty`）时同步清空对应模块旧缓存；而未登录（`notLoggedIn`）或解析改版异常（`error`）时严格保留本地历史缓存并显著标注提示，阻断误清空风险。
- **学期基准日期大幅跳变与冲突确认保护 (`ScheduleProvider`)**：
  - 引入 `evaluateSemesterCalibration` 纯逻辑评估器，当检测到教学历起始日与顶栏当前周次反推存在 >= 7 天偏差，或新学期基准与本地已存基准发生跨学期 / >= 7 天大幅跳变时，弹出二次确认对话框，防止脏数据静默覆盖用户正常学期设置。

### Security & Compliance
- **主密钥写后回读强校验与异常隔离 (`AppCryptoService`)**：
  - 修复首次生成主密钥写入安全存储后回读为 `null` 时未校验的隐患，实现写后强一致校验；若回读为空或不一致立即抛出 `CryptoKeyException` 并阻止未持久化临时密钥落盘，消除重启永久解密死锁。
- **Windows 撤回授权冷启动补偿擦除 (`LegalService`)**：
  - 针对 Windows 桌面端运行期 WebView2 独占锁导致部分网络缓存无法立即物理删除的问题，引入 `pendingWindowsWipeKey` 标记与冷启动早期补偿擦除机制，并在下次启动未初始化 WebView2 前彻底清空残留。
- **合规协议与文档修订 (合规文本 `2026-11-06.v7`)**：
  - 《隐私政策》更新生效日期至 2026 年 11 月 6 日（`v7`）；澄清剪贴板仅在用户主动点击复制时按指令写入、不主动读取；精确区分 Android Keystore 硬件级与 Windows DPAPI 凭据隔离存储机制；修正 Windows 本地路径为 `%APPDATA%\Jinhua Assistant OpenSource Community\金花助手`。
  - `README.md` 与工程构建指南补充 Windows 构建 VS 2022 C++ ATL/MFC 组件要求，更新 Android 包体积说明（约 20 MB）。
  - CI/CD 流水线构建门禁扩展覆盖 PR 编译，Release 发布产物自动化生成 `SHA256SUMS.txt` 校验清单并随 Release 上传。

## [2.3.0-pre1] - 2026-11-05

本版本为 `v2.3.0` 首个开发预览版（Developer Preview 1），重点完成全量教务同步全异步架构重构以及千行核心界面的模块化解耦拆分，彻底消除大同步时的 UI 冻结现象，并大幅提升工程代码健康度与可维护性。

### Added
- **跨端原生消息通道与全量异步同步架构**：
  - 在 `WebViewPlatformAdapter` 中打通双端原生通信桥梁（Android 原生 `JavascriptChannel('JinhuaBridge')` 与 Windows WebView2 原生 `window.chrome.webview.postMessage`）。
  - 支持阶段性同步进度实时分发与界面感知（动态呈现教学周识别、课表提取、学业成绩与考试安排进度），消除大同步过程中的 UI 冻结与操作阻滞。
- **模块化排布算法与单元测试套件**：
  - 新增 `schedule_layout_test.dart` 8 组核心用例，全方位断言多课程动态分栏、智能聚类排布、活跃周次优先及邻近度排序规则。

### Refactored
- **强智解析层异步化升级 (`ParserService`)**：
  - 彻底废除同步阻塞式 `XMLHttpRequest`，全面升级为基于原生 `fetch` 与 `AbortController` 20 秒超时保护的异步拉取（`fetchHtmlAsync` 与 `fetchHtmlAsyncPost`）。
  - 同步脚本支持桥接通知与直接返回值双轨兼容。
- **千行大页面单一职责解耦拆解**：
  - **`WebViewLoginScreen` (1156 行 ➔ 198 行)**：解耦为 `webview_constants.dart`（常量与业务路由枚举）、`webview_platform_adapter.dart`（双端生命周期与桥接通道）、`webview_sync_coordinator.dart`（同步业务编排与弹窗）、`webview_nav_bar.dart`（导航与地址条）与 `webview_bottom_bar.dart`（操作栏与进度指示）。
  - **`ScheduleScreen` (1145 行 ➔ 380 行)**：解耦为 `schedule_types.dart`（布局项模型与纯函数排布算法）、`week_switcher_capsule.dart`（双端周次切换胶囊）、`schedule_empty_guide.dart`（无课表空态引导）、`week_status_banner.dart`（非本周回到本周提醒条）、`weekday_header.dart`（星期与公历日期表头）、`section_timeline.dart`（13 节次时间轴）与 `schedule_day_column.dart`（单天网格与课程并列定位卡片）。

## [2.2.0] - 2026-11-05

金花助手 `v2.2.0` 正式版发布！本版本为重大可靠性与安全性升级，全面加固端侧数据生命周期、引入强智 DOM 解析层离线回归测试套件、构建同步三态可观测诊断与数据自愈闭环、并封堵 WebView 与安全存储多处边界隐患。

### Added
- **DOM 解析器离线自动化回归测试套件 (`parser_test/`)**：
  - 基于 Node 24 原生测试运行器与 JSDOM 构建 18 组核心用例，覆盖课表双容器过滤、4 节连排、表尾大跨度备注行阻断、五级制/二级制成绩折算、无座位号考试日程与登录负例。
  - 全面集成至 GitHub Actions CI 质量门禁流水线。
- **全量同步三态/四态可观测诊断**：
  - 建立 `SyncModuleStatus` 可观测模型，明确区分成功（`ok`）、当前学期无数据（`empty`）、统一身份认证未登录（`notLoggedIn`）与改版/解析异常（`error`）。
  - 增强未登录嗅探能力，自动识别 CAS 金智认证重定向特征并在同步完成弹窗中逐项展示诊断状态与错误摘要。
- **解密失败可见化与数据自愈闭环 (`DecryptionErrorView`)**：
  - 当设备密钥变更或本地密文损坏时，界面直观提示异常原因，提供“重新同步”与“一键重置损坏数据并重置主密钥”两条恢复通路，无需重新签署法律协议。
- **课程详情周次矩阵动态上限**：
  - 弹窗矩阵支持动态上限 `max(20, currentWeek, ...weeks)`，消除教学周超过 20 周时被截断的问题。

### Security & Privacy
- **内存生命周期严格闭环**：
  - 撤回知情同意（《个人信息保护法》第 15 条）与重置损坏数据时，同步调用全量 Provider 的 `clearAll()` 彻底销毁内存状态与错误标记，杜绝界面残留。
- **主密钥安全存储与单飞死锁修复**：
  - 修复首次写入安全存储时吞异常问题，增加写入回读校验与真实异常重抛，阻止未持久化临时密钥加密落盘；修复 Single-Flight 机制在异常时的死锁问题，允许失败后安全重试。
- **WebView 安全与脚本注入 Origin 守卫**：
  - 修复 `WebViewLoginScreen.isAllowedUrl` 空 Host 漏洞，严格限制 `*.xaut.edu.cn` HTTPS 白名单并增加 Windows 拦截即时 `_winController.stop()`。
  - 为 5 个注入解析脚本头部增加 `_originGuardJs` 严格校验 `proto === 'https:'` 与 `host.endsWith('.xaut.edu.cn')`，彻底封堵导航竞态与恶意外跳。
  - 脚本执行增加 30 秒硬超时保护，防范校内教务接口冻结。
- **Windows 桌面端撤回清理路径更正**：
  - 更正为真实的 `getApplicationSupportDirectory` 目录（`%APPDATA%\Jinhua Assistant OpenSource Community\金花助手`），并自动递归清理文件。
- **敏感数据脱敏**：
  - 移除安全日志中密钥的十六进制字符串插值，测试用例与样本数据全面剥离教师姓名等个人信息。

### Fixed
- **课表冷启动同步时间保护**：
  - 修复每次启动无条件将「上次同步时间」篡改为当前时间的缺陷，仅在去重数据确有变动时静默回写，保持同步时间戳准确。
- **全量同步跨 iframe 探测**：
  - 预检课表、成绩、考试表格统一改用跨 frame 搜索函数 `findTableAcrossFrames`，消除子页面嵌套 iframe 时的误报改版错误。
- **考试查询学期参数兜底**：
  - 优先取下拉框显式选中的学期或当前教学周学期，兜底取成绩列表中字典序最大的最新学期，避免盲目取首项导致高年级考试列表为空。
- **复杂单/双周混合格式解析**：
  - `qiangzhi_parser.js` 与 Dart 侧统一升级为基于子段的单双周判定与向前继承解析算法（覆盖 `"1-4单周,5-8周"`、`"1-3,5-7单周"`、`"1-8单周,9-16双周"` 等）。

### Changed
- 统一成绩同步弹窗与成绩界面的 GPA/学分数据源为 Dart 侧 `gradesProvider.overallSummary` 计算口径，并清理废弃的 `xaut_cached_grade_summary` 冗余写入。
- 优化考试模型（`ExamItem`）时间解析性能，采用 `Expando` 弱引用缓存时间正则解析结果，降低高频重复正则开销。
- Android `release` 构建类型在无签名密钥配置时优雅回退至 `debug` 签名，保证非发版分支的 CI 编译产物不报错。

## [2.2.0-rc2] - 2026-11-05

本版本为 `v2.2.0` 候选发布版（Release Candidate 2），全面加固端侧数据生命周期状态管理、完善主密钥单飞恢复与写入校验、增强跨 iframe 与单双周解析鲁棒性，并补齐 Windows 端撤回授权真实路径清理。

### Security & Privacy
- 修复撤回知情同意及重置损坏数据后的内存状态残留：调用 `LegalService.revokeAndClearAll()` 与 `StorageService.resetCorruptedData()` 时，同步调用全量 Provider 的 `clearAll()` 彻底清空内存，杜绝界面残留。
- 加固主密钥安全存储与单飞恢复：修复主密钥写入失败时吞掉真实存储异常的隐患，增加写入回读校验与真实异常重抛；修复 Single-Flight 机制在异常时的死锁问题，确保异常后可正常重试。
- 注入脚本顶层 Origin 安全守卫：为 5 个注入解析脚本头部增加严格的协议（`https:`）与域名后缀（`*.xaut.edu.cn`）运行时自检，从 JS 底层阻断导航竞态与恶意外跳。
- 修正 Windows 桌面端撤回授权数据清理路径：更正为真实的 `getApplicationSupportDirectory` 目录（`%APPDATA%\Jinhua Assistant OpenSource Community\金花助手`）并自动递归清理文件，兼容无原生环境的测试。

### Fixed
- 修复课表冷启动无条件篡改「上次同步时间」的缺陷：增加 `updateSyncTime` 可选控制，启动时若去重规范化后数据无变动则不回写，保持同步时间戳准确。
- 修复全量一键同步脚本在子页面触发时未跨 `iframe` 探测表格导致误报改版错误的问题：预检统一改用跨 frame 搜索函数 `findTableAcrossFrames`。
- 修复考试安排查询学期参数兜底错误：优先取下拉框显式选中的学期或当前教学周学期，最后兜底取成绩列表中字典序最大的最新学期，避免盲目取首项导致高年级考试列表为空。
- 修复单/双周混合格式（如 `"1-4单周,5-8周"`、`"1-3,5-7单周"`）解析缺陷：`qiangzhi_parser.js` 与 Dart 侧统一升级为基于子段的单双周判定与向前继承解析算法。

### Changed
- 统一成绩同步弹窗与成绩界面的 GPA/学分数据源：弹窗直接使用 Dart 侧 `gradesProvider.overallSummary` 计算口径，并清理废弃的 `xaut_cached_grade_summary` 冗余写入字段。
- 课程详情弹窗周次矩阵支持动态上限（`max(20, currentWeek, ...weeks)`），消除大于 20 周时周次被截断的问题。
- 优化考试模型（`ExamItem`）时间解析性能：采用 `Expando` 弱引用缓存时间正则解析结果，大幅降低列表排序与状态演算中的重复正则消耗。
- Android `release` 构建类型在无签名密钥配置时优雅回退至 `debug` 签名，保证非发版分支的 CI 编译产物不报错（发版 Tag 仍保持 SHA-256 证书强校验）。

## [2.2.0-rc1] - 2026-11-04

本版本为 `v2.2.0` 候选发布版（Release Candidate 1），重点实现强智教务同步结果三态可观测性诊断、未登录自动嗅探，以及本地落盘数据解密失败可见化与数据自愈恢复闭环。

### Added
- 建立全量同步三态/四态可观测模型（`SyncModuleStatus`）：严格区分成功（`ok`）、当前学期无数据（`empty`）、统一身份认证未登录（`notLoggedIn`）与改版/解析异常（`error`）。
- 增强教务未登录嗅探能力：静默抓取时能自动识别 CAS 金智认证重定向特征（`authserver/login`、`casLoginForm`），并在同步时优先提示完成登录。
- 新增解密失败用户可见化与数据自愈恢复组件（`DecryptionErrorView`）：当设备安全密钥变更或密文损坏时，课表、成绩与考试界面直观提示异常原因，提供“重新同步”与“一键重置损坏数据并重置主密钥”两条恢复通路（无需重新通读法律协议）。
- 新增针对同步三态反序列化与 Provider 解密自愈流程的自动化单元测试。

### Reliability
- 修复 `StorageService.loadCourses` 吞掉 `CryptoException` 的缺陷，解密异常向上透出至业务层，杜绝损坏时静默展示空课表造成的误解。
- 为 WebView 脚本执行硬拦截门禁增加 30 秒超时保护，防范校内教务接口无响应时界面永久冻结。

### Changed
- 重构全量同步完成与异常弹窗：逐行明确展示课表、教学周、成绩、考试各个模块的细化诊断状态与错误摘要。

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

[Unreleased]: https://github.com/korty258/xaut-assistant/compare/v2.3.0-rc1...HEAD
[2.3.0-rc1]: https://github.com/korty258/xaut-assistant/compare/v2.3.0-pre1...v2.3.0-rc1
[2.3.0-pre1]: https://github.com/korty258/xaut-assistant/compare/v2.2.0...v2.3.0-pre1
[2.2.0]: https://github.com/korty258/xaut-assistant/compare/v2.1.2...v2.2.0
[2.2.0-rc2]: https://github.com/korty258/xaut-assistant/compare/v2.2.0-rc1...v2.2.0-rc2
[2.2.0-rc1]: https://github.com/korty258/xaut-assistant/compare/v2.2.0-pre1...v2.2.0-rc1
[2.2.0-pre1]: https://github.com/korty258/xaut-assistant/compare/v2.1.2...v2.2.0-pre1
[2.1.2]: https://github.com/korty258/xaut-assistant/compare/v2.1.1...v2.1.2
[2.1.1]: https://github.com/korty258/xaut-assistant/compare/v2.1.0...v2.1.1
[2.1.0]: https://github.com/korty258/xaut-assistant/compare/v2.0.3...v2.1.0
[2.0.3]: https://github.com/korty258/xaut-assistant/compare/v2.0.2...v2.0.3
[2.0.2]: https://github.com/korty258/xaut-assistant/compare/v2.0.1...v2.0.2
[2.0.1]: https://github.com/korty258/xaut-assistant/compare/v2.0.0.beta3...v2.0.1
[2.0.0.beta3]: https://github.com/korty258/xaut-assistant/compare/v2.0.0.pre1...v2.0.0.beta3
[2.0.0.pre1]: https://github.com/korty258/xaut-assistant/releases/tag/v2.0.0.pre1
