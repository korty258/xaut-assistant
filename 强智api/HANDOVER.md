# 西安理工大学 (XAUT) 教务 App 开发 - 任务交接卡 (Handover)

## 一、项目基础信息
* **目标项目**：西安理工大学跨平台教务客户端（支持 Windows `.exe` 与 Android `.apk`）
* **技术选型**：Flutter 原生跨端方案 (Material 3 + 原生 WebView 注入)
* **核心工作区**：`c:\Users\tong\Documents\教务app\`
* **教务接口目录**：`c:\Users\tong\Documents\教务app\强智api\`

## 二、当前已完成事项 (100% 验证通过)
1. **教务系统逆向与接口分析**：
   * 教务核心路由为 `/jsxsd/`（强智新学分制系统）。
   * 课表路由：`/jsxsd/xskb/xskb_list.do`（`table#timetable`，包含 `.kbcontent`）。
   * 成绩路由：`/jsxsd/kscj/cjcx_list`（`table#dataList`，已具备 GPA 与加权平均分计算）。
   * 考试路由：`/jsxsd/xsks/xsksap_query` 及其内嵌页 `/jsxsd/xsks/xsksap_list`（参数 `xnxqid`，已具备自动跨 iframe 递归定位）。
2. **生产级解析脚本**：
   * `c:\Users\tong\Documents\教务app\强智api\qiangzhi_parser.js` 已包含三大函数：
     * `parseQiangZhiCourses(document)`
     * `parseQiangZhiGrades(document)`
     * `parseQiangZhiExams(document)`
   * 经 Git 版本控制归档（Tag: `v1.0.0-verified`）。
3. **本地开发环境状态**：
   * Flutter SDK (3.47.8) 已配置好官方国内加速镜像。
   * Visual Studio 2026 C++ 桌面工具链已全部点亮绿勾 `[√]`（具备编译 Windows `.exe` 能力）。
   * Android SDK 已就绪，仅差在 Android Studio SDK Tools 中勾选 `Android SDK Command-line Tools (latest)` 并执行 `flutter doctor --android-licenses`。

## 三、新对话接入提示词（直接复制给新 Agent）
```text
我正在开发西安理工大学 (XAUT) 的跨平台教务 App（Flutter 方案，支持 Windows 与 Android）。
前序工作已全部完成并保存在本地磁盘：
1. 项目根目录：c:\Users\tong\Documents\教务app\
2. 教务解析脚本与文档：c:\Users\tong\Documents\教务app\强智api\qiangzhi_parser.js 和 README.md
   （课表、成绩、考试日程三大解析规则已全部在西理工真实教务系统控制台 100% 验证通过）。
3. 环境状态：Flutter SDK 与 Windows C++ 工具链已全部变绿就绪。

请读取上述目录中的 qiangzhi_parser.js 和 README.md，接着带我继续推进下一步：创建 Flutter 工程骨架、将解析器集成进 assets、并实现 WebView 登录鉴权与原生课表 UI！
```
