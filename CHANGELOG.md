# Changelog

本文件记录**金花助手 (Jinhua Assistant)** 的所有重要版本变更。

格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 规范，版本号管理遵循 [语义化版本 2.0.0 (SemVer)](https://semver.org/lang/zh-CN/) 及项目确立的三阶段发布流转规范（`Pre -> RC -> Release`）。

## [Unreleased]

## [2.3.7] - 2026-11-13

金花助手 `v2.3.7`（脱敏诊断摘要入口前移优化补丁版）发布！本版本优化了客户端脱敏诊断摘要的触发层级，将原本隐藏在「关于与法律条款」第 4 个标签页（「开源致谢」）最底部的诊断按钮大幅前移，用户现在可直接从主页面右上角「...」菜单一键查看诊断摘要，或在进入「关于与法律条款」时无需切换标签或滚动即可在底部直接操作。

### UX Improvements
- **一级菜单直达脱敏诊断摘要 (`DiagnosticsDialog`)**：
  - 将诊断摘要弹窗抽离为共享组件 `DiagnosticsDialog`；
  - 在课表、成绩、考试三大主页面的右上角「更多操作 (`...`)」菜单中新增「查看诊断摘要」入口，点击即可直接弹出并复制脱敏诊断报告。
- **关于页底部常驻诊断与反馈入口 (`LegalGateScreen`)**：
  - 将「查看并复制诊断摘要」与「复制开源仓库 / 问题反馈地址」按钮从「开源致谢」正文底部移至「关于与法律条款」常驻底栏，无需切换 Tab 或长距离滚动即可操作；
  - 同步更新 `.github/ISSUE_TEMPLATE/bug_report.yml` 缺陷申报指引文案。

### Tests
- **组件交互测试增强 (`widget_test.dart`)**：
  - 更新 `LegalGateScreen` 关于页测试，验证不切换「开源致谢」Tab 且不滚动即可在底部直接点击诊断摘要按钮；
  - 新增 `ScheduleScreen` 右上角更多菜单直接打开诊断摘要弹窗的组件测试，Flutter 全量测试增至 **121 项**。

## [2.3.6] - 2026-11-13

金花助手 `v2.3.6`（本地存储密码学 AAD 键名强绑定与安全加固正式版）发布！本版本将端侧 AES-256-GCM 密文信封升级至 `ENC:v2:`，把 `SharedPreferences` 存储键名作为 AEAD AAD（Additional Authenticated Data）参与完整性认证，彻底杜绝跨键密文替换风险，同时保持对存量 `ENC:v1:` 密文与旧版明文 JSON 的平滑自动升级兼容。

### Security
- **密文信封升级 `ENC:v2:` 与 AAD 键名强绑定 (`AppCryptoService`)**：
  - `encrypt()` / `decrypt()` 支持可选 `associatedData`（AEAD AAD）参数，密文信封版本号升级为 `ENC:v2:`；
  - `saveEncryptedString()` / `loadEncryptedString()` 自动将存储键名（`xaut.sp.v2:<key>`）绑定进 AES-256-GCM 认证标签计算，跨键迁移或替换密文时直接触发 AEAD 认证失败并抛出 `CryptoException`；
  - **向下兼容与自动升级**：保留对历史 `ENC:v1:` 密文（无 AAD）及旧版明文 JSON 的读取兼容，并在读取时自动平滑升级重存为绑定当前键名的 `ENC:v2:` 密文；
  - **严格拒绝未知密文版本**：遇到未知 `ENC:` 版本前缀（非 `ENC:v1:` / `ENC:v2:`）时显式抛出异常，坚决杜绝降级按明文透出。

### Tests
- **密码学与兼容性回归测试 (`app_crypto_service_test.dart`)**：
  - 新增 5 项单元测试，覆盖 AAD 匹配/失配/缺失校验、空明文+AAD 加解密、SharedPreferences 跨键密文替换拦截、`ENC:v1:` 兼容解密与自动升级 `ENC:v2:`，以及未知 `ENC:` 前缀拒绝；
  - Flutter 单元与组件测试用例总数扩充至 **120 项** 全绿通过。

## [2.3.5] - 2026-11-12

金花助手 `v2.3.5`（西理工官方学业成绩与 GPA 算法对齐正式版）发布！本版本与西安理工大学教务处官方盖章《学生学业成绩表》进行全真逐项公式对账，彻底解决同门课程正考与补考/重修去重、补考及格官方 0 绩点保持、五级制 90/80/70/60 标准分换算以及官方加权均分分子规则，实现 App 端动态加权平均分、平均 GPA、总学分及课程门数与教务处官方成绩单 100% 精确一致。

### Calculation Alignment (Official XAUT Rules)
- **同门课程初修与补考/重修去重 (`GradeCalculator.calculateSummary`)**：
  - 以课程代码（或课程名）为键进行去重聚合，当一门课存在多次考试记录（如正考不及格 + 补考及格）时，优先保留绩点高者；绩点相同时保留数值成绩/折算分更高者；
  - 杜绝多条考试记录导致学分被重复累加、拉大分母并拉低平均 GPA 的问题；
  - 课程总数准确反映去重后的有效门数，与官方成绩单完全对齐。
- **信赖官方绩点与补考 0 绩点保持**：
  - 直接信赖教务系统针对课程行给出的非负绩点，坚决消除补考及格（60 分）官方 0.0 绩点被误用兜底公式算出额外绩点的缺陷；
  - 百分制兜底公式同步校准为西理工官方基准 `(分数 - 45) / 10`。
- **五级制折算标准分官方公式映射 (`fiveLevelGradeMap`)**：
  - 严格对齐官方换算公式 `标准分 = 绩点 * 10 + 45`：
    - 优/优秀：90 分（4.5 绩点）；
    - 良/良好：80 分（3.5 绩点）；
    - 中/中等：70 分（2.5 绩点）；
    - 及格：60 分（1.5 绩点）；
    - 不及格：0 分（0.0 绩点）。
- **官方加权平均成绩分子规则**：
  - 严格对齐官方成绩单算式：若课程有效绩点 `effGpa > 0`，其得分参与加权平均成绩分子累加；
  - 若课程有效绩点 `effGpa == 0`（如补考及格 60 分或不及格课程），其学分正常计入加权分母，但分子得分为 `0.0`。

### Tests
- **全真官方规则测试覆盖 (`grade_calculator_test.dart`)**：
  - 新增匿名合成数据集全真对账用例（覆盖两学期 28 条原始考试记录、同门正考不及格与补考及格、五级制及全学期汇总），100% 吻合官方单学期与全学期 GPA、加权均分、总学分与门数；
  - 同步更新现有测试对五级制 90 分标准分映射的断言；
  - Flutter 单元与组件测试用例总数扩充至 **115 项** 全绿通过。

## [2.3.4] - 2026-11-12

金花助手 `v2.3.4`（稳定性、数据安全与可观测性正式版）发布！本版本全面修复安全存储故障路径（引入 Fail-Closed 主密钥安全门禁与同步时间戳先加密后落盘机制）、重构授权撤回与冷启动残留补偿机制、增加成绩与考试分模块独立同步时间戳与界面显示、引入 100% 纯端侧脱敏诊断摘要服务及 GitHub 缺陷申报模板，并完成 CI/CD 编译缓存与网络容错加固。

### Security & Data Safety (Fail-Closed)
- **安全存储故障阻断落盘 (Fail-Closed Master Key)**：
  - 重构 `AppCryptoService._loadOrCreateMasterKey()`，消除生产环境下 `MissingPluginException` 被静默降级为临时内存密钥的安全缺陷；
  - 生产环境下当安全存储通道不可用时，严格抛出 `CryptoKeyException` 阻断落盘，防止生成重启后永久无法解密的新数据；
  - 仅在显式单元测试标记（`AppCryptoService.allowInMemoryTestKey = true`）下允许内存测试密钥。
- **课表同步落盘时序原子化 (`StorageService.saveCourses`)**：
  - 调整写入顺序：严格在 `AppCryptoService.saveEncryptedString` 加密写入成功后才更新 `xaut_last_sync` 时间戳，杜绝落盘失败导致时间戳虚假刷新的状态不一致问题。
- **结构化撤回清理结果与冷启动残留补偿 (`RevokeCleanupResult`)**：
  - 重构 `AppCryptoService.destroyMasterKey()` 返回物理删除真实布尔结果；
  - `LegalService.revokeAndClearAll()` 升级为返回结构化 `RevokeCleanupResult`，明确反馈 Preferences 清理、主密钥销毁、WebView 数据与 Windows 目录清理的各分项状态；
  - 针对 Windows 文件占用或安全存储异常导致的未删净项，设置 `pendingMasterKeyWipeKey` 与 `pendingWindowsWipeKey` 标志，在下一次冷启动最早期由 `runPendingWipeIfNeeded()` 执行补偿擦除；
  - `LegalGateScreen` 根据清理结果向用户提供准确的反馈提示（完整清理 vs 待冷启动补偿清理）。

### Observability & UI
- **成绩与考试分模块独立同步时间戳**：
  - `StorageService` 新增 `xaut_last_grades_sync` 与 `xaut_last_exams_sync` 持久化读写，并在清空数据或重置时安全擦除；
  - `GradesProvider` 与 `ExamsProvider` 分别维护 `lastSyncTime`，仅在同步成功或权威空数据写入密文后刷新时间戳，失败与未登录严格保留原时间戳；
  - `GradesScreen` 与 `ExamsScreen` 顶栏实时展示分模块上次同步时间（如 `同步于 11-12 10:30`），方便用户掌握教务数据新鲜度。
- **100% 纯本地脱敏诊断摘要服务 (`DiagnosticsService`)**：
  - 新增 `DiagnosticsService`，内存暂存最近一次教务同步的脱敏遥测数据（触发模式、耗时、各模块状态码与异常类别，绝不记录原始 stack trace 或 HTML 内容）；
  - 提供 `buildDiagnosticReport()` 输出格式化 Markdown 摘要（包含 App 版本、条款版本、平台、WebView2 状态、各模块同步时间戳与最近遥测）；
  - 严格隐私保障：经过 100% 纯本地规则过滤，绝对不含任何学号、密码、Cookie、课程名、成绩、GPA、考试名或原始教务 HTML；
  - 在「关于与法律条款」页面开源致谢卡片底部新增「查看并复制诊断摘要」与「复制开源仓库 / 问题反馈地址」便捷入口，配合确认弹窗与剪贴板一键复制。

### CI/CD & Engineering
- **GitHub Issue 模板与反馈闭环**：
  - 新增 `.github/ISSUE_TEMPLATE/bug_report.yml`，引导用户提供运行平台、版本号、复现步骤及脱敏诊断摘要。
- **README 常见问题与排查指南 (FAQ)**：
  - 新增 FAQ 章节，覆盖校园网 / WebVPN 访问说明、Windows WebView2 与 VC++ 运行库说明、`.ics` 系统日历导入指南及问题反馈途径。
- **CI Android 编译容错与 Gradle 缓存加固**：
  - 在 `.github/workflows/ci_cd.yml` 的 `build_android` 任务中启用 `actions/setup-java@v5` 的 `cache: 'gradle'`；
  - 为 `flutter build apk` 配置 3 次弹性重试机制与 120 秒网络超时（`GRADLE_OPTS`），彻底消除 GitHub 下载 Kotlin 编译器等外部依赖时的偶发 504 Gateway Timeout 导致的流水线误报。

### Tests
- **新增 14 项安全与诊断测试用例**：
  - 新增 `xaut_app/test/diagnostics_service_test.dart`（6 项用例），验证脱敏诊断摘要生成、标准异常类型识别、隐私零泄漏及分模块同步时间戳持久化；
  - `app_crypto_service_test.dart` 扩充 4 项生产 Fail-Closed 单元测试（插件通道缺失拦截、落盘阻断、回读篡改与主密钥删除）；
  - `legal_service_test.dart` 扩充 3 项 `RevokeCleanupResult` 分项清理与冷启动补偿擦除测试；
  - `widget_test.dart` 扩充 1 项诊断摘要弹窗交互组件测试；
  - Flutter 单元与组件测试用例总数扩充至 **114 项** 全绿通过；
  - Node 24 JSDOM 解析器回归测试持续保持 **27 项** 全绿。

## [2.3.3] - 2026-11-09

金花助手 `v2.3.3` 正式版发布！本版本重点进行解析层与状态协调层的模块化重构解耦：收敛 GPA 与学分加权至统一的 Dart 计算器、纯化 JS 为无副作用 DOM 提取器（彻底杜绝双端规则漂移）、清理未使用的死字段、统一跨模块 Bridge 与 CAS 认证工具；同时在工程层面引入 GitHub Dependabot 自动化 pub / npm 依赖安全巡检机制。

### Refactored & Improved
- **GPA 与学分演算权责单一化 (`GradeCalculator`)**：
  - 新建 `GradeCalculator`，统筹西安理工大学百分制、五级制（优/良/中/及格/不及格）与二级制（合格/通过）折算规则；
  - 纯化 `qiangzhi_parser.js` 中 `parseQiangZhiGrades`：JS 仅负责 DOM 原始字段抽取，不再在 WebView 渲染线程中执行重复的浮点加权运算；
  - 彻底消除 JS 端与 Dart 端关于 GPA 折算算法的双重维护与潜在规则漂移隐患。
- **解析层模块化解耦与 Facade 门面化 (`ParserService`)**：
  - 将庞大的 `ParserService`（原 1422 行）解耦为职责单一的独立子模块：
    - `parser/sync_script_builder.dart`：专注跨端 Bridge 注入脚本与异步管线拼接；
    - `parser/sync_result_parser.dart`：专注 JSON 反序列化与实体模型组装；
    - `parser/sync_models.dart`：收敛四态同步状态机与跨模块结果定义；
    - `parser_service.dart`：精简为不足 120 行的高内聚 Facade 门面，完全向后兼容原有静态 API。
- **清除代码冗余与死字段清理**：
  - 彻底移除 `SyncAllResult.gradesSummary` 死字段与相关无用装配逻辑；
  - 提取单一的 `checkAuthJs` 统一认证守卫常量，消除原先在多个注入脚本中重复手写的 4 份 `checkAuth` 函数。

### CI/CD & Engineering
- **引入 GitHub Dependabot 依赖自动化检测**：
  - 新增 `.github/dependabot.yml`，对主工程 `/xaut_app` 的 pub 依赖实施每周（weekly）自动化健康扫描；
  - 对 `/parser_test` 的 npm 测试依赖实施每月（monthly）版本巡检；
  - 针对 Windows C++ 原生插件（`webview_windows`）与 Android Keystore 根密钥托管插件（`flutter_secure_storage`）配置严格的 semver-major 升级保护；
  - 自动复用既有的 GitHub Actions PR 双端编译门禁（`Lint & Tests` + `Build Android` + `Build Windows`），实现依赖升级自动提 PR、全链路编译与单测拦截验证。

### Tests
- **新增纯 Dart GPA 演算单元测试套件**：
  - 新增 `xaut_app/test/grade_calculator_test.dart`（2 项纯 Dart 单元测试），全量覆盖混合制五级/二级折算、缓考/缺考/免考过滤与 0 学分安全处理；
  - Flutter 单元与组件测试用例总数扩充至 **100 项** 全绿通过；
  - 同步更新 Node.js 解析器回归测试，保持 **27 项** 持续全通。
## [2.3.2] - 2026-11-08

金花助手 `v2.3.2` 正式版发布！本版本重点重构考试日程同步状态机，精确区分「空表壳、权威空列表与网络异常」，杜绝弱网与异常网络下误清空本地考试缓存；同时完善 Windows 桌面端运行环境（CMake 随包自动分发 MSVC 运行时 DLL、WebView2 运行时预检与缺失诊断引导卡片），统一合规声明措辞并扩充全套状态机回归测试。

### Fixed
- **考试同步状态机状态精确区分与防误清加固 (`ParserService`)**：
  - 重构 `fetchExamScheduleAsync`，显式拆分并严格维护 `hadTransportError`（网络传输失败）、`confirmedEmptyExamList`（权威空列表确认）与 `isNotLoggedIn`（未登录）三元独立状态；
  - 引入 `isAuthoritativeExamListDoc` 辅助断言，仅当查询列表响应中包含带有合法考试表头（`课程名称`/`考试课程`/`考试时间`）或明确含 `"未查询到数据"` 的表格且全量请求零传输失败时，才返回权威 `empty` 状态允许清空本地旧缓存；
  - 阻断当前页 DOM 与查询外壳页 `/jsxsd/xsks/xsksap_query` 的无数据 `#dataList` 空表壳误触 `confirmedEmptyExamList`；
  - 修复 `buildExamsInjectionScript` 中因当前页存在空表壳将网络 `error` 强转为 `empty` 的逻辑缺陷，单模块同步直接信赖状态机判定，杜绝弱网误清旧缓存；
  - 候选学期遍历时即使发生前序网络重试错误，只要后续候选成功解析到考试记录即按 `ok` 成功返回。

### Added & Improved
- **Windows 桌面端运行环境自主完备与可视化诊断引导**：
  - 更新 Windows `CMakeLists.txt`，构建时自动扫描并随包分发 MSVC C++ 运行时 DLL（`msvcp140.dll`、`vcruntime140.dll`、`vcruntime140_1.dll`），彻底杜绝新装纯净系统因缺失 VC++ Redistributable 导致启动闪退；
  - 在 `WebViewPlatformAdapter` 与 `WebViewLoginScreen` 中新增 Windows Edge WebView2 运行时安装状态检测；当检测到系统未安装 WebView2 时，呈现可视化嵌入式诊断卡片与一键直达微软官方下载引导，告别白屏静默卡死；
  - 完善 `README.md` 与发布说明中关于 Windows 桌面端运行环境（WebView2 与 x64 架构）的系统需求声明。

### Compliance & Documentation
- **统一系统级密钥存储与安全合规表述**：
  - 更新 `THIRD_PARTY_NOTICES.md` 中 `flutter_secure_storage` 说明为「系统安全根密钥托管 (Android Keystore 硬件级 / Windows DPAPI 用户凭据隔离)」，与应用内置开源致谢条款保持严格一致；
  - 更新 `README.md` 中数据安全表述为「大幅降低离线明文泄露风险与非法窥视」，与隐私政策权威表述严格对齐。

### Tests
- **补齐考试状态机与缓存保护回归测试套件**：
  - Node.js JSDOM 解析器测试扩充至 **27 项**（新增测试组 6：覆盖查询外壳空表壳网络失败、当前页空表壳网络失败、权威空列表、多候选跨学期重试成功、混合网络失败防误清、全量成功权威空表 6 大边界场景）；
  - Flutter 单元与组件测试套件扩充至 **98 项**，全量覆盖 `buildExamsInjectionScript` 强转消除断言、`buildSyncAllInjectionScript` 权威空列表状态机断言，以及 `WebViewSyncCoordinator.syncExams` 在 error、timeout、failure 下保留旧考试与 empty 下清空旧考试的断言。

## [2.3.1] - 2026-11-08

金花助手 `v2.3.1` 正式版补丁发布！本版本重点修复在登录教务系统首页一键拉取全部时考试日程获取失败的缺陷，全面提炼共享异步考试拉取管线，增强 DOM 解析容错与表头自适应定位，并扩充回归测试套件。

### Fixed
- **修复教务首页一键拉取全部时考试日程拉取短路缺陷**：
  - 修复登录教务系统首页后「一键拉取全部」因无参直接请求 `/jsxsd/xsks/xsksap_list` 返回空 `#dataList` 表格而短路跳过 `/jsxsd/xsks/xsksap_query` 学期提取与 POST 兜底的缺陷；
  - 提炼共享异步考试拉取管线 `fetchExamScheduleAsync`（五级学年学期 `xnxqid` 决议 + `xsksap_query` 元数据提取 + `GET`/`POST` 双通道自动兜底 + 回退学期二次重试），并同步赋能「仅同步本页 (考试)」；
  - 修复 `qiangzhi_parser.js` 中 `parseQiangZhiTeachingWeek` 学期下拉框包含前置 `"---请选择---"` 空选项时短路覆盖有效 `option[selected]` 的问题。

### Changed & Improved
- **增强强智教务考试表格 DOM 解析与跨 frame 容错 (`qiangzhi_parser.js`)**：
  - 优化 `parseQiangZhiExams` 跨同源 iframe 扫描逻辑，优先选择包含非空数据行的目标表格；
  - 严格过滤外层无表头或无数据行的布局嵌套 table；
  - 支持前 3 行动态扫描定位有效表头，自适应处理包含前置通知横幅或修饰行的复杂强智页面。

### Tests
- **解析器与注入测试套件扩充**：
  - Node.js JSDOM 回归测试扩充至 **20 项**（新增嵌套布局 table 过滤、前置横幅表头扫描与前置空选项下拉框学期识别断言）；
  - Flutter 自动化单元与组件测试套件保持 **96 项** 全绿，全面覆盖异步拉取管线与跨端桥接异常拦截断言。

## [2.3.0] - 2026-11-07

金花助手 `v2.3.0` 正式版发布！本版本为重大架构与可靠性升级：全面完成强智教务全量异步同步重构（彻底消除 UI 冻结）、千行核心界面单一职责解耦、异步桥接 `requestId` 生命周期隔离、四态缓存防误清纵深加固、学期基准跳变与课表原子确认保护，以及主密钥强一致校验与 Windows 撤回授权冷启动补偿擦除闭环。

### Added
- **双端原生消息桥接与全量异步同步架构**：
  - 打通 Android `JavascriptChannel('JinhuaBridge')` 与 Windows WebView2 `window.chrome.webview.postMessage` 原生通信通道，废除同步阻塞式 `XMLHttpRequest`，升级为 `fetch` + `AbortController` 异步拉取。
  - 支持阶段性同步进度实时透出（教学周识别、课表提取、学业成绩、考试安排），消除全量同步时的界面卡顿。
- **学期基准变更冲突检测与原子确认保护 (`ScheduleProvider` & `WebViewSyncCoordinator`)**：
  - 引入 `evaluateSemesterCalibration` 纯逻辑评估器：当校历起始日与顶栏周次反推存在 `>= 7` 天偏差，或与本地基准发生跨学期 / `>= 7` 天跳变时弹出二次确认对话框。
  - 确认流程前置至课表落盘之前：若用户选择「保持原设置」，同时保留原课表与原学期基准，杜绝新课表与旧开学日错位混用；仅识别到学期名而无周次时调用 `setSemesterNameOnly` 并准确提示手动校准。
- **工程质量门禁与构建校验增强**：
  - GitHub Actions 构建门禁扩展覆盖 `pull_request` 双端编译校验，Release 发布自动生成并附带 `SHA256SUMS.txt` 校验清单。
  - Flutter 自动化单元与组件测试扩充至 **96 项**（新增课表排布算法、异步桥接路由与超时取消、`success: false` 异常拦截、生命周期销毁、单飞防抖、四态缓存与密钥强校验回归套件）。

### Changed & Refactored
- **千行大页面单一职责解耦拆分**：
  - `WebViewLoginScreen`（1156 行 ➔ 218 行）拆分为平台适配器、同步协调器、导航地址栏与底部进度操作栏组件；页面加载状态（`isLoadingNotifier`）与数据同步状态（`isSyncingNotifier`）彻底解耦。
  - `ScheduleScreen`（1145 行 ➔ 380 行）拆分为纯函数排布算法、双端切周胶囊、空态引导、回到本周横幅、星期公历表头、13 节时间轴与单日网格列组件。
- **异步桥接请求生命周期隔离与精确路由 (`WebViewPlatformAdapter` & `ParserService`)**：
  - 引入全局递增 `requestId` 精准路由与 `window.__jinhuaAbortTask` 取消钩子，超时与已取消任务的迟到响应直接丢弃；在 Android/Windows 页面跨页跳转（排除 `#hash` 锚点变化）、刷新或销毁时主动取消挂起任务。
  - 全量同步（`syncAll`）强制通过独立异步请求拉取默认全量课表与成绩数据源，严禁直接读取当前浏览页 `document`，防止页面筛选态污染本地全量缓存。

### Fixed
- **纵深阻断异常响应误清空本地缓存**：
  - 桥接层第一时间拦截 `type == 'error'` 与 `parsed['success'] == false` 全局异常包；解析层将 `SyncModuleStatus.fromString` 默认回退收紧为 `SyncModuleStatus.error`，严格按四态语义仅在显式合法 `empty` 时清空对应模块旧缓存，`notLoggedIn` 与 `error` 始终保留本地历史缓存。
- **防抖自锁与页面销毁竞态修复**：
  - 修复非业务页智能提示弹窗过早记录冷却时间导致弹窗内「一键同步全部」被 3 秒冷却自锁拦截的问题，并增加单飞互斥锁。
  - 调整 `WebViewLoginScreen.dispose()` 释放顺序并补充 `isDisposed` 状态守卫，杜绝退出页面时向已销毁 `ValueNotifier` 写入触发异常。

### Security & Compliance
- **主密钥写后回读强一致校验 (`AppCryptoService`)**：
  - 首次生成主密钥写入系统安全存储后立即执行回读比对，若为空或不一致立即抛出 `CryptoKeyException` 并阻断未持久化临时密钥加密落盘，消除重启后永久解密死锁隐患。
- **Windows 撤回授权冷启动早期补偿擦除 (`LegalService`)**：
  - 针对运行期 WebView2 文件句柄占用场景，引入 `pendingWindowsWipeKey` 标记并在下次冷启动初始化 WebView2 前自动执行二次物理擦除。
- **合规文本 `2026-11-06.v7` 对齐**：
  - 更新《隐私政策》（`v7`）、《用户服务协议》与《开源软件致谢》，明确剪贴板仅按用户点击指令写入、不主动读取；客观区分 Android Keystore 硬件级托管与 Windows DPAPI 当前登录用户凭据隔离，并对齐 Windows `%APPDATA%` 真实存储路径与构建环境说明。

## [2.3.0-rc2] - 2026-11-07

本版本为 `v2.3.0` 第二候选发布版（Release Candidate 2），重点闭环异步桥接全局异常 `success: false` 拦截与四态缓存防误清纵深加固、页面销毁与 Windows 校内导航生命周期对齐、学期确认与新课表写入原子一致性以及合规文本精细化对齐。

### Fixed
- **彻底阻断全局脚本异常包 `success: false` 误判为 `empty` 清空本地缓存 (`WebViewPlatformAdapter` & `ParserService`)**：
  - 跨端桥接层在消息分发第一时间拦截 `parsed['success'] == false` 与 `type == 'error'` 异常包，以 `StateError` 拒绝挂起异步任务，彻底阻断异常结果流入业务解析流程。
  - 解析层纵深防御：严禁将缺失显式 `status` 的异常对象或未知状态默认判为 `empty`，`SyncModuleStatus.fromString` 默认回退值统一收紧为 `SyncModuleStatus.error`；`parseSyncAllResult`、`parseCourseSyncResult`、`parseGradesResult` 与 `parseExamsDetailedResult` 全面加固，任何携带 `success: false` 或异常诊断的载荷均严格判定为 `error` 状态并保留既有本地缓存。
- **页面销毁与同步生命周期安全闭环 (`WebViewSyncCoordinator` & `WebViewPlatformAdapter`)**：
  - 调整 `WebViewLoginScreen.dispose()` 销毁顺序为先释放原生平台适配器并取消挂起任务，再释放同步调度协调器。
  - `WebViewSyncCoordinator` 引入 `isDisposed` 状态守卫与 `_setSyncingState` 安全分发辅助方法，杜绝在同步请求执行中或页面关闭后读写已销毁 `ValueNotifier` 抛出异常。
  - Windows 端补齐校内链接点击跳转的主动任务取消：在 WebView2 URL 监听器中检测跨页导航（排除同页 `#hash` 锚点变化与首次启动加载），主动取消正在进行的同步任务，与 Android 行为严格对齐。
- **学期基准变更确认与新课表写入原子一致性 (`ScheduleProvider` & `WebViewSyncCoordinator`)**：
  - 重构 `_applyDetectedWeekCalibration` 评估确认流程并前置至写入本地课表之前：当检测到跨学期或开学日大幅跳变且用户选择「保持原设置」时，同时保留原课表与原学期基准，杜绝新课表与旧学期日期错位混用。
  - 修复未识别到开学日或周次但识别到新学期名称时误报“已自动对齐第 X 周”的问题；`ScheduleProvider` 补充 `setSemesterNameOnly`，提示用户手动校准开学日。

### Security & Compliance
- **合规文本客观措辞与跨端安全根密钥说明精细化对齐**：
  - 《用户服务协议》与《开源软件致谢》准确阐述跨平台安全根密钥托管形态：明确 Android 端为 Keystore 硬件级密钥库托管，Windows 端为 DPAPI 绑定当前登录用户凭据隔离。
  - 《隐私政策》收敛正文中少数绝对化修饰词为客观严谨的工程与密码学表述（防止系统备份通道导出、大幅降低离线明文泄露风险、使残留密文在密码学上失效不可还原、明确 Windows 端被占用缓存含下次冷启动补偿清理等）。保持合规门禁版本 `2026-11-06.v7` 不变。

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

[Unreleased]: https://github.com/korty258/xaut-assistant/compare/v2.3.7...HEAD
[2.3.7]: https://github.com/korty258/xaut-assistant/compare/v2.3.6...v2.3.7
[2.3.6]: https://github.com/korty258/xaut-assistant/compare/v2.3.5...v2.3.6
[2.3.5]: https://github.com/korty258/xaut-assistant/compare/v2.3.4...v2.3.5
[2.3.4]: https://github.com/korty258/xaut-assistant/compare/v2.3.3...v2.3.4
[2.3.3]: https://github.com/korty258/xaut-assistant/compare/v2.3.2...v2.3.3
[2.3.2]: https://github.com/korty258/xaut-assistant/compare/v2.3.1...v2.3.2
[2.3.1]: https://github.com/korty258/xaut-assistant/compare/v2.3.0...v2.3.1
[2.3.0]: https://github.com/korty258/xaut-assistant/compare/v2.2.0...v2.3.0
[2.3.0-rc2]: https://github.com/korty258/xaut-assistant/compare/v2.3.0-rc1...v2.3.0-rc2
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
