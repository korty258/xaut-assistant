# 金花助手 (Jinhua Assistant)

<p align="center">
  <img src="xaut_app/assets/logo.png" alt="Logo" width="108" height="108" />
</p>

<p align="center">
  <strong>基于 Flutter 3 的现代化跨端原生教务助手客户端</strong><br>
  课表智能日程 · 成绩学分分析 · 考试安排速查
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Version-v2.1.2-brightgreen" alt="Version">
  <a href="https://github.com/korty258/xaut-assistant/actions/workflows/ci_cd.yml">
    <img src="https://github.com/korty258/xaut-assistant/actions/workflows/ci_cd.yml/badge.svg" alt="CI/CD Status">
  </a>
  <img src="https://img.shields.io/badge/Flutter-3.47+-02569B?logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/Platform-Android%20|%20Windows-green" alt="Platform">
  <img src="https://img.shields.io/badge/Architecture-arm64--v8a%20(19MB)-blue" alt="Architecture">
  <img src="https://img.shields.io/badge/License-GPL--3.0-blue.svg" alt="License">
</p>

<p align="center">
  <a href="https://github.com/korty258/xaut-assistant/releases/latest"><strong>📥 前往 Releases 下载最新安装包 (Android APK / Windows 绿色版)</strong></a>
</p>

---

## 🌟 项目亮点

- 🔒 **零第三方服务端 / 隐私安全**：完全在本地设备运行，直连西安理工大学强智教务系统，不收集、不上报任何账号、密码或个人敏感信息。
- 🔐 **全量学业数据 AES-256-GCM 硬件级落盘加密**：课表日程、成绩与绩点 (GPA)、期末考试安排在设备本地均采用 AEAD AES-256-GCM 算法加密存储；主密钥受硬件安全隔离保护并支持撤回时“密码学粉碎 (Crypto-Shredding)”，杜绝离线物理导出与明文窥视。
- 📆 **RFC 5545 标准系统日历导出**：支持一键将整学期课程表与期末考试日程导出为标准 `.ics` 日历文件；完美兼容苹果日历、小米日历、华为日历、OPPO/vivo、Outlook 及 Google 日历，支持自定义上课与考前提醒时间，无缝联动手机系统桌面小组件与智能手表手环。
- 🛡️ **知情同意门禁与合规防护**：深度参照《中华人民共和国个人信息保护法》(PIPL) 与网络安全合规规范，首次启动必须经过法律门禁 (`LegalGateScreen`) 完整阅读并主动勾选同意，内置完全离线可查阅的《用户服务协议》、《隐私政策》与《免责声明》；未经用户明确授权不读取或存储任何教务凭据，且支持随时在「关于与法律条款」中查阅或一键**撤回知情同意并清空本地缓存**。
- ⚡ **一键全量同步 & 周次自动校准**：在教务主页即可通过原生 WebView 注入解析引擎，一键并发拉取 **课表 + 成绩 + 考试** 三大模块，并自动识别顶栏当前教学周（如 `2026-2027-1 第9周`）反推本学期第 1 周周一基准日期。
- 🗓️ **教学周随日期自动递增 & 丝滑翻周体验**：每次启动与跨日唤醒均根据系统日期自动计算并跳转至最新教学周，表头「周一 ~ 周日」下方实时展示对应公历日期（如 `10/26`）；支持**手机端左右滑动切周**与 **Windows 桌面端 `<` `>` 快捷翻周箭头**，浏览其他周次时可一键「回到本周」，同时支持双模式手动校准开学日。
- 📅 **智能排课引擎与「所有周」聚合**：
  - **仅本周模式**：过滤非本周课程，本周有课时段 100% 独占显示，清爽无干扰。
  - **所有周模式**：同一节次多门课程智能叠层，当前周课程优先满宽展示，配备 `+N` 叠层角标与弹窗即时周次轮播切换，杜绝挤压成乱码细条。
  - **去重与清洗**：自动剔除强智教务系统隐藏二维码与重复备用容器，精准识别 4 节连排实验课。
- 📊 **分学期动态 GPA 演算 & 等级制成绩兼容**：切换学期筛选 Chip 即可实时重算**单学期 / 累计**加权平均分、平均绩点 (GPA) 与已修学分；完整兼容西理工实验、实训等 **五级制（优/良/中/及格）** 与 **二级制（合格/通过）** 课程学分绩点统计。
- 📝 **考试倒计时角标与「待考优先」智能排序**：自动解析考试起止时间，将未考科目按开考时间升序排在最前并展示醒目的 `考试中` / `今天` / `明天` / `还有 X 天` 倒计时角标，已结束科目自动沉底弱化。
- 🌙 **跨端原生与深浅色自适应**：完整适配系统浅色 / 深色模式 (`ThemeMode.system`)，支持 Windows 桌面端 (MSVC AOT / WebView2 / 微软雅黑清晰渲染) 与 Android 端 (纯 arm64-v8a 极致裁剪优化，包体积约 19.4 MB)。

---

## 📱 核心功能与交互说明

| 课表主界面（本周/所有周智能叠层） | 考试安排速查 | 成绩学分统计 | 教务一键全量同步 |
| :---: | :---: | :---: | :---: |
| 智能高亮当前周课程，支持周次切换 | 校区地点、考试时间与监考安排 | 自动 GPA 绩点与学分加权计算 | 原生登录穿透，支持一键并发同步 |

---

## 🛠️ 技术架构

```text
xaut-assistant/
├── CHANGELOG.md                # 版本变更日志 (遵循 Keep a Changelog 1.1.0)
└── xaut_app/                   # Flutter 跨平台主工程 (Android & Windows)
    ├── lib/
    │   ├── models/             # 课程 (Course)、成绩 (Grade)、考试 (Exam) 数据模型
    │   ├── services/           # 解析 (ParserService)、端侧加密 (AppCryptoService)、日历导出 (CalendarExportService)、存储 (StorageService)、合规门禁 (LegalService)
    │   ├── providers/          # ScheduleProvider, GradesProvider, ExamsProvider
    │   ├── screens/            # 课表、成绩、考试、登录同步容器、法律门禁 (LegalGateScreen)
    │   └── widgets/            # 智能课程卡片、课程详情弹窗、教学周选择抽屉、日历导出弹窗 (CalendarExportDialog)
    ├── assets/
    │   ├── js/                 # 内置打包注入的强智教务解析脚本 (qiangzhi_parser.js)
    │   ├── legal/              # 离线合规文本 (用户协议、隐私政策、免责声明、开源致谢 Markdown)
    │   └── logo.png            # 金花原创软件标识
    ├── android/                # Android 宿主配置与原生资源 (包名 io.github.korty258.jinhua_assistant)
    └── windows/                # Windows C++ 宿主与 Edge WebView2 集成
```

---

## 🚀 编译与本地运行

### 运行环境要求
- [Flutter SDK](https://flutter.dev/) (>= 3.47.0，CI 固定为 3.47.8)
- [Dart SDK](https://dart.dev/) (>= 3.13.7)
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

## 🏷️ 版本发布流转规范 (Release Lifecycle)

为保障客户端在广大师生日常使用中的稳定性与数据安全性，本项目建立三阶段版本发布流转体系：

```text
Pre (预览测试版) ──> RC (发布候选版) ──> Official Release (正式版)
```

| 阶段 | Tag 命名规范 (SemVer 2.0) | GitHub 发布类型 | 核心定位与准出标准 |
| :--- | :--- | :--- | :--- |
| **Pre 预览版** | `vX.Y.Z-pre1`、`vX.Y.Z-pre2` | `Pre-release` | 新特性快速研发与原型试用，用于敏捷测试与问题暴露。 |
| **RC 候选版** | `vX.Y.Z-rc1`、`vX.Y.Z-rc2` | `Pre-release` | 功能冻结（Feature Freeze），开展全量自动化测试、边界异常修复、合规审查与稳定性验收。 |
| **正式版** | `vX.Y.Z` | `Latest Release` | 验收通过的生产级全量发布版本，具备完整的安全加固与稳定质量保障，打上置顶 `Latest` 徽章。 |

> **版本命名建议**：遵循 SemVer 2.0 规范使用中划线（如 `v2.2.0-pre1`、`v2.2.0-rc1`），保证各平台与 Git 语义化排序天然满足 `pre < rc < 正式版`。CI/CD 工作流已全面配置自动化分类与徽章分配。

---

## ⚠️ 免责声明 (Disclaimer)

1. **非官方声明与数据读取原则**：
   - 本项目为西安理工大学在校学生出于学习与便利目的开发的非官方开源工具，**非西安理工大学官方产品**，亦未获得西安理工大学或强智科技的官方授权或隶属关联。
   - 本软件仅通过学校官方网页界面，读取用户本人登录后可见的课表、成绩与考试信息；不调用未公开的 API 接口，不绕过验证码或统一身份认证。
2. **标识与商标权明确**：
   - 本应用采用独立设计的「金花」原创金色花朵图标作为唯一软件标识，**当前版本不使用西安理工大学官方校徽图案或任何官方机构专属徽标**。
   - “西安理工大学”、“西理工”及强智教务系统等中英文名称及商标权益均归其法定权利人所有；本项目在文档与界面中提及相关名称仅出于描述软件适用环境与兼容目标的事实性说明，不构成任何商标使用、官方背书或授权合作意图。
3. **隐私安全与个人信息保护 (PIPL 合规)**：
   - 软件运行过程中的所有身份认证与教务数据交互均发生在用户本地设备与学校官方教务系统之间，**不架设任何第三方中转服务器，绝不在云端收集或存储任何用户凭据**。
   - 依据《中华人民共和国个人信息保护法》，首次使用必须经由法律门禁主动勾选确认同意。用户可随时在软件设置中查阅完整条款或一键撤回授权。Windows 桌面端由于免安装便携架构，如需彻底清除内嵌 WebView2 浏览器缓存与 Cookie，可手动删除 `%APPDATA%\io.github.korty258.jinhua_assistant` 目录及程序同级目录下的 `*.WebView2` 文件夹。
4. **合理合规使用**：请合理使用本软件，严禁用于任何高频恶意抓取、网络攻击或危害学校信息化系统正常运行的行为。
5. **权利人通知与联系方式**：如权利人认为本项目内容涉嫌侵犯其合法权益，或有任何合规建议，请通过电子邮件联系开发者：`korty666@outlook.com`，我们将在核实后第一时间作出合规调整。

---

## 📄 开源许可证

本项目基于 [GNU General Public License v3.0 (GPL-3.0)](LICENSE) 开源。
