# 西安理工大学 (XAUT) 强智教务 App 项目接力与架构备忘录

> **项目状态**：`v1.0.1-released`（西理工小助手正式版 · GPL-3.0）  
> **更新时间**：2026-10-30  
> **适用场景**：在新会话开启时，由 AI 助手首先读取本文件，即可无缝接续全部上下文与工程状态。

---

## 一、项目核心概况

* **项目名称**：西理工小助手 (`xaut-assistant`)
* **开源仓库**：`https://github.com/korty258/xaut-assistant`
* **项目版本**：`v1.0.1` (Build 2)
* **开源协议**：GNU General Public License v3.0 (GPL-3.0)
* **应用图标**：西安理工大学官方紫色圆形校徽（已精准裁切居中并适配 Android 多分率 mipmap、Windows .ico 与 Web 全规格图标）
* **项目定位**：西安理工大学 (XAUT) 跨端原生教务客户端（Flutter 3.47.8 架构，支持 Windows `.exe` 与 Android `.apk`）。
* **教务系统**：湖南强智新学分制系统 (`jsxsd`)，包含金智 CAS 统一身份认证。
* **认证与同步策略**：**原生 WebView 鉴权 + JS 解析脚本跨 iframe 自动穿透注入**。

---

## 二、工作区核心目录结构

```text
C:\Users\tong\Documents\教务app\
├── PROJECT_HANDOVER.md               # 本接力备忘文档
├── 强智api\                          # 原始逆向解析套件与说明
│   ├── README.md                     # 教务实测特征文档
│   ├── qiangzhi_parser.js            # 核心生产级全功能解析脚本（课表/成绩/考试）
│   └── test_verify.js                # 解析逻辑与 HTML 标签清洗单元测试
└── xaut_app\                         # Flutter 跨平台主工程
    ├── pubspec.yaml                  # 注册 assets/js/qiangzhi_parser.js
    ├── assets\js\
    │   └── qiangzhi_parser.js        # 打包至 App 内置资产的解析脚本
    ├── lib\
    │   ├── main.dart                 # MultiProvider 注入与 Material 3 蓝色主题
    │   ├── models\
    │   │   ├── course.dart           # 课程模型（周次集合、节次跨度、哈希色彩）
    │   │   ├── grade.dart            # 成绩明细与学分/GPA统计模型
    │   │   └── exam.dart             # 考试模型（已严格去除无用座位号）
    │   ├── services\
    │   │   ├── storage_service.dart  # SharedPreferences 本地持久化缓存
    │   │   └── parser_service.dart   # JS 注入脚本生成与结果多层反序列化
    │   ├── providers\
    │   │   ├── schedule_provider.dart# 课表状态机（仅本周/全课表模式、周次控制）
    │   │   ├── grades_provider.dart  # 成绩与学期筛选状态机
    │   │   └── exams_provider.dart   # 考试日程状态机
    │   ├── screens\
    │   │   ├── home_screen.dart      # Material 3 底部三栏主容器（课表/成绩/考试）
    │   │   ├── schedule_screen.dart  # 课表主界面（支持智能防重叠横向分栏）
    │   │   ├── grades_screen.dart    # 学业表现、学期筛选与成绩列表
    │   │   ├── exams_screen.dart     # 考试时间、校区、考场地点卡片
    │   │   └── webview_login_screen.dart # Windows(Edge WebView2) / Android 双端原生登录与同步
    │   └── widgets\
    │       ├── course_card.dart      # 课程卡片（自适应子列并列与本周状态标签）
    │       ├── course_detail_dialog.dart # 课程详情弹窗与 1-20 周活跃点阵
    │       └── week_selector_sheet.dart  # 教学周快速切换抽屉
    └── windows\CMakeLists.txt        # 已配置 -D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS
```

---

## 三、重大踩坑与已落地的关键技术方案（在新会话中务必保持）

1. **课表 HTML 二维码干扰与标签清洗**：
   * 西理工真实教务系统单元格 `.kbcontent` 内嵌了二维码弹窗 `<div class="item-box" style="display:none..."><img src="/jsxsd/jsxx/ewmck..."/></div>`。
   * 解析器在 DOM 层采用 `cloneNode` 递归移除 `.item-box`，并在正则层执行深度清洗与 `ewmck` 行过滤，确保课程名称绝对纯净。
2. **拒绝画蛇添足的考试座位号**：
   * 西理工强智系统不含考场座位号分配。`ExamItem`、`parseQiangZhiExams` 及 UI 均已彻底移除所有“座位号”与“座位未分配”逻辑，仅保留考场地点、校区、时间、批次与监考教师。
3. **首发体验与假数据清理**：
   * 彻底删除了“体验演示数据”功能。无本地数据时，主页展示美观的“首次使用导入指引”，直接引导用户登录强智教务同步。
4. **课程重叠冲突解决方案（仅本周 / 全课表）**：
   * **【仅本周】模式**（默认）：彻底过滤非本周课程，本周有课时段独占 100% 宽度，零冲突、无重叠。
   * **【全课表】模式**：引入 `LayoutBuilder` 动态测量与**区间着色分栏算法 (`_computeCourseLayout`)**，同一节次若存在 2 门重叠课程，卡片自动按 50% 宽度并列排放，并分别标注 `[本周]` 与 `[非本周]`，杜绝文字重叠。
5. **Windows MSVC 2026 编译兼容**：
   * 已在 `windows/CMakeLists.txt` 添加 `-D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS`，抑制 VS 2026 对 `webview_windows` 协程特性的弃用报错。
6. **Android NDK 与镜像加速**：
   * 已安装官方完整 Android NDK `28.2.13676358`。
   * 在 `android/settings.gradle.kts` 与 `android/build.gradle.kts` 配置了阿里云 Maven 镜像。
7. **强智多容器重复解析与课程折半分栏修复 (v1.1.1)**：
   * 强智系统同一单元格同时塞入 `.kbcontent`（详细版）与 `.kbcontent1`（简版备用容器），原解析器全部提取导致同一课程产生 2 条记录，触发防重叠分栏折半（各占 50%）。
   * **修复方案**：JS 解析器锁定只查 `.kbcontent`，严格排除 `.kbcontent1`；过滤 `-` 等无意义占位符；Flutter `ScheduleProvider` 加入智能合并去重逻辑（优先保留完整教室地点），并对历史本地缓存实现启动即自愈。
8. **节次连排标记误识别为周次漏洞修复 (v1.1.2)**：
   * 在类似 `15-16(周)[07-08-09-10节]` 的多节连排课程中，原正则直接在全局字符串提取所有连续数字，导致节次 `07-08` 与 `09-10` 被错误解析为第 7、8、9、10 周活跃，造成第 9 周显示了原本在第 15-16 周才上的实验课。
   * **修复方案**：在周次解析前彻底剥离中括号 `\[.*?\]` 内的节次部分；升级节次计算器以支持 `07-08-09-10` 连排语法（自动识别 4 节跨度）；在 Flutter `ScheduleProvider` 启动初始化中加入历史缓存周次修正自愈算法。
9. **同步页面自适应高亮与全量一键同步 (v1.1.3)**：
   * **快捷导航自适应高亮**：彻底移除“我的课表”写死高亮样式，改为根据 WebView 实时 URL 动态匹配当前模块（教务主页/我的课表/成绩查询/考试安排）并精准高亮；
   * **默认主选项：一键同步全部**：在注入 JS 中实现跨页面同源同步抓取与 DOM 解析，一次点击同时全自动拉取并解析 **课表 + 成绩 + 考试** 三大模块数据并批量入库；
   * **智能识别当前页同步**：原“更多同步”重构为智能识别按钮，根据当前页面动态切换为【同步当前课表】/【同步当前成绩】/【同步当前考试】，实现所见即所同。
10. **全模块统一数据清空与二次防误触确认交互 (v1.1.4)**：
   * 在 **课表主页**、**考试安排页** 以及 **学业成绩页** 顶部右上角统一提供了【更多操作】菜单（图标为 3 个垂直小圆点 `⋮`）；
   * 包含醒目的红色【清空课表数据】/【清空考试数据】/【清空成绩数据】按钮，并在点击后弹出二次防误触确认对话框，防止误触丢失本地缓存，清空后可随时重新同步。
11. **Android 纯 arm64-v8a Release 架构专属打包 (v1.2.0)**：
   * 采用 `--target-platform android-arm64 --release` 编译，启用 AOT 机器码优化与图标字体摇树裁剪 (`Tree-shaking`)；
   * 体积从原 Debug 版的 `172.5 MB` 骤降至 **`17.0 MB`**（缩减 90%），冷启动与页面渲染性能显著提升；
   * 解决 Windows 中文目录引起 Dart AOT Snapshotter 编码异常的编译技巧：利用 `subst X:` 映射虚拟 ASCII 驱动器配合 `kotlin.incremental=false` 完成顺畅编译。
12. **课表“所有周”移动端智能层叠聚合与文案重构 (v1.2.1)**：
   * **文案全面升级**：将晦涩的“全课表”统一定名为更通俗易懂的 **【所有周】**（与【仅本周】相呼应）；
   * **彻底告别细条挤压**：重构 `_computeCourseLayout` 布局引擎。在“所有周”模式下，同一时间段内存在多门课程轮替（如 1-8 周、11-14 周、15-16 周不同课程）时，**优先保证当前周课程独占 100% 宽度**，绝不将其均分拆成不可读的细条；
   * **多课角标与弹窗即时切换**：卡片右上角增加高饱和度 `+N` 叠层角标，点击卡片弹出的详情对话框顶部提供横向 ChoiceChip，可一键切换查看该时段共存的每一门课程、周次活跃点阵及考场/教室；
   * **手机顶栏响应式自适应**：精简 AppBar 标题宽度与药丸边距，在 360-390dp 各种安卓手机屏幕上标题均不再被截断。
13. **教务主页跨页面全量一键同步考试日程修复 (v1.2.2)**：
   * **问题根因**：强智系统的 `/jsxsd/xsks/xsksap_query` 页面是一个外层表单容器，包含学期下拉列表与指向真实列表的 `iframe`。在教务主页后台 `fetch` 该页面时，由于游离的 DOM 不会触发子资源 iframe 加载，若直接抓取未带参数的 `/jsxsd/xsks/xsksap_list`，强智服务端返回空表格或重定向，导致一键同步时考场日程无法抓取；
   * **修复方案**：升级 `buildSyncAllInjectionScript` 中的考试抓取逻辑。先拉取 `xsksap_query` 静态 HTML 并解析其中的 `iframe[src]` 与选中学期 `select[name="xnxqid"]`，若无法获取则智能兜底同步出来的最新成绩所属学期（如 `2026-2027-1`），拼接带参数的 `/jsxsd/xsks/xsksap_list?xnxqid=...` 并分别执行 GET/POST 穿透提取，确保在教务主页点击「一键同步全部」即可一次性完整同步课表、成绩与考试安排。
14. **开源标准套件与隐私防护规范 (v1.0.1)**：
   * 建立了规范的根目录 `.gitignore`、`LICENSE` (GPL-3.0) 与精美中文 `README.md`；
   * 经代码扫描校验，源码与本地资产已实现 0 硬编码个人学号、姓名、密码与 Cookies，架构完全采用端侧直连与本地 SharedPreferences 存储，无任何中间服务器，符合开源安全标准。
15. **应用名称与品牌形象重塑 (v1.0.1)**：
   * 软件正式定名为 **「西理工小助手」**（更新 Android 桌面标签、Windows 窗口标题及 Flutter MaterialApp title）；
   * 将西安理工大学官方紫色圆形校徽高精裁切（Center 512, 404.5，Radius 308.5），采用抗锯齿边缘羽化透明通道处理，生成了 Android 5 档位 mipmap 启动图标、Windows 6 分辨率多帧 `app_icon.ico` 及 Web PWA 图标；
   * 开源协议升级确定为 **GNU General Public License v3.0 (GPL-3.0)**，版本号锁定为 `v1.0.1`。

---

## 四、本地产物位置（桌面就绪）

* **Android Release APK (arm64-v8a)**：
  - `C:\Users\tong\Desktop\西理工小助手_v1.0.1_arm64-v8a.apk`（17.0 MB 生产版）
  - `C:\Users\tong\Desktop\西安理工大学教务_xaut_app_arm64-v8a.apk`（已同步覆盖为 17.0 MB 生产版）
  - `C:\Users\tong\Desktop\西安理工大学教务_xaut_app.apk`（已同步覆盖为 17.0 MB 生产版）
* **Windows 桌面快捷方式**：`C:\Users\tong\Desktop\西安理工教务(Windows).lnk`
* **Windows 绿色便携包**：`C:\Users\tong\Desktop\xaut_app_Windows桌面端\`（已同步最新全功能版本）

---

## 五、后续可拓展方向（供新会话参考）

1. **ICS 日历文件导出**：将当前课表和考试日程导出为 `.ics` 标准日历格式，支持一键添加到系统日历或手机日历。
2. **多学期课表切换**：在课表顶部支持选择 2024-2025-1、2024-2025-2 等历史与未来学期课表。
3. **空闲教室查询**：结合强智系统空教室检索接口，拓展自习室查找模块。
