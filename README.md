# 金花助手 (Jinhua Assistant)

<p align="center">
  <img src="xaut_app/assets/logo.png" alt="Logo" width="108" height="108" />
</p>

<p align="center">
  <strong>基于 Flutter 3 的现代化跨端原生教务助手客户端</strong><br>
  课表智能日程 · 成绩学分分析 · 考试安排速查
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Version-v2.0.0.pre2-brightgreen" alt="Version">
  <img src="https://img.shields.io/badge/Flutter-3.47+-02569B?logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/Platform-Android%20|%20Windows-green" alt="Platform">
  <img src="https://img.shields.io/badge/Architecture-arm64--v8a%20(17MB)-blue" alt="Architecture">
  <img src="https://img.shields.io/badge/License-GPL--3.0-blue.svg" alt="License">
</p>

<p align="center">
  <a href="https://github.com/korty258/xaut-assistant/releases/latest"><strong>📥 前往 Releases 下载最新安装包 (Android APK / Windows 绿色版)</strong></a>
</p>

---

## 🌟 项目亮点

- 🔒 **零第三方服务端 / 隐私安全**：完全在本地设备运行，直连西安理工大学强智教务系统，不收集、不上报任何账号、密码或个人敏感信息。
- ⚡ **一键全量同步 & 周次自动校准**：在教务主页即可通过原生 WebView 注入解析引擎，一键并发拉取 **课表 + 成绩 + 考试** 三大模块，并自动识别顶栏当前教学周（如 `2026-2027-1 第9周`）反推本学期第 1 周周一基准日期。
- 🗓️ **教学周随日期自动递增 & 丝滑翻周体验**：每次启动与跨日唤醒均根据系统日期自动计算并跳转至最新教学周，表头「周一 ~ 周日」下方实时展示对应公历日期（如 `10/26`）；支持**手机端左右滑动切周**与 **Windows 桌面端 `<` `>` 快捷翻周箭头**，浏览其他周次时可一键「回到本周」，同时支持双模式手动校准开学日。
- 📅 **智能排课引擎与「所有周」聚合**：
  - **仅本周模式**：过滤非本周课程，本周有课时段 100% 独占显示，清爽无干扰。
  - **所有周模式**：同一节次多门课程智能叠层，当前周课程优先满宽展示，配备 `+N` 叠层角标与弹窗即时周次轮播切换，杜绝挤压成乱码细条。
  - **去重与清洗**：自动剔除强智教务系统隐藏二维码与重复备用容器，精准识别 4 节连排实验课。
- 📊 **分学期动态 GPA 演算 & 等级制成绩兼容**：切换学期筛选 Chip 即可实时重算**单学期 / 累计**加权平均分、平均绩点 (GPA) 与已修学分；完整兼容西理工实验、实训等 **五级制（优/良/中/及格）** 与 **二级制（合格/通过）** 课程学分绩点统计。
- 📝 **考试倒计时角标与「待考优先」智能排序**：自动解析考试起止时间，将未考科目按开考时间升序排在最前并展示醒目的 `考试中` / `今天` / `明天` / `还有 X 天` 倒计时角标，已结束科目自动沉底弱化。
- 🌙 **跨端原生与深浅色自适应**：完整适配系统浅色 / 深色模式 (`ThemeMode.system`)，支持 Windows 桌面端 (MSVC AOT / WebView2 / 微软雅黑清晰渲染) 与 Android 端 (纯 arm64-v8a 极致裁剪优化，包体积仅 ~17 MB)。

---

## 📱 核心功能与交互说明

| 课表主界面（本周/所有周智能叠层） | 考试安排速查 | 成绩学分统计 | 教务一键全量同步 |
| :---: | :---: | :---: | :---: |
| 智能高亮当前周课程，支持周次切换 | 校区地点、考试时间与监考安排 | 自动 GPA 绩点与学分加权计算 | 原生登录穿透，支持一键并发同步 |

---

## 🛠️ 技术架构

```text
xaut-assistant/
└── xaut_app/                   # Flutter 跨平台主工程 (Android & Windows)
    ├── lib/
    │   ├── models/             # 课程 (Course)、成绩 (Grade)、考试 (Exam) 数据模型
    │   ├── services/           # WebView 注入服务 (ParserService) 与 本地持久化 (StorageService)
    │   ├── providers/          # ScheduleProvider, GradesProvider, ExamsProvider
    │   ├── screens/            # 课表、成绩、考试、WebView 登录同步容器
    │   └── widgets/            # 智能课程卡片、课程详情弹窗、教学周选择抽屉
    ├── assets/js/              # 内置打包注入的强智教务解析脚本 (qiangzhi_parser.js)
    ├── android/                # Android 宿主配置与原生资源
    └── windows/                # Windows C++ 宿主与 Edge WebView2 集成
```

---

## 🚀 编译与本地运行

### 运行环境要求
- [Flutter SDK](https://flutter.dev/) (>= 3.24.0)
- [Dart SDK](https://dart.dev/) (>= 3.5.0)
- **Windows 构建**：Visual Studio 2022/2026 (包含 C++ 桌面开发套件)
- **Android 构建**：Android SDK (API 34+) 及 Android NDK (r28+)

### 1. 克隆工程并拉取依赖
```bash
git clone https://github.com/korty258/xaut-assistant.git
cd xaut-assistant/xaut_app
flutter pub get
```

### 2. 运行单元测试
```bash
flutter test
```

### 3. Windows 桌面端编译
```bash
# 启动调试
flutter run -d windows

# 编译 Release
flutter build windows
```

### 4. Android 端编译 (推荐 arm64-v8a 单架构)
```bash
flutter build apk --release --target-platform android-arm64
```
> **提示（Windows 路径包含中文时）**：如遇到 Dart AOT Snapshotter 路径编码问题，可通过 `subst X: .` 挂载虚拟磁盘后执行编译。

---

## ⚠️ 免责声明 (Disclaimer)

1. 本项目为西安理工大学在校学生出于学习与便利目的开发的非官方开源工具，**非西安理工大学官方产品**。
2. **商标与校徽权益**：应用中使用的西安理工大学校徽图案与学校中英文名称等知识产权均归西安理工大学所有。本项目仅作为在校生学习生活辅助软件进行识别性展示，非商业盈利使用。
3. **隐私与数据安全**：软件运行过程中的所有身份验证与教务数据交互均发生在用户个人设备与学校官方服务器之间，**不经由任何第三方代理服务器，不存储任何用户密码**。
4. 请合理使用本软件，严禁用于任何高频恶意抓取、网络攻击等可能影响学校系统正常运行的行为。
5. 如学校系统前端结构调整导致数据解析失败，欢迎提交 Issue 或 Pull Request。

---

## 📄 开源许可证

本项目基于 [GNU General Public License v3.0 (GPL-3.0)](LICENSE) 开源。
