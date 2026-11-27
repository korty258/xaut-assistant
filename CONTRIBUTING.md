# 贡献指南 (Contributing Guide)

感谢你关注并愿意参与**金花助手 (Jinhua Assistant)** 的开源建设！在提交 Issue 或 Pull Request 之前，请花 2 分钟阅读以下核心约束与开发流程。

---

## 1. 西理工业务与产品绝对红线

为保证项目定位清晰、合规安全且贴合西安理工大学（XAUT）教务系统真实情况，所有 PR 必须严格遵守：

1. **无考场座位号**：西安理工大学强智教务系统不分配考场座位号，请勿在数据模型、解析脚本、UI、`.ics` 导出或测试中捏造、预留或展示“座位号”字段。
2. **无冬夏令时切换**：学校全年执行固定作息时间（每日固定 6 大节 / 13 小节：`08:00`、`10:10`、`12:10`、`14:10`、`16:10`、`19:00`），请勿引入冬夏令时切换逻辑。
3. **数据导出边界**：课表与考试安排支持标准 RFC 5545 `.ics` 导出；**学业成绩仅限应用内查看与动态 GPA 演算，不接受任何结构化成绩导出（CSV/Excel/JSON/Markdown 等）功能**。
4. **纯本地与隐私安全（PIPL）**：
   - 零自建后端、零遥测统计，WebView 导航白名单严格锁定 `*.xaut.edu.cn`；
   - 本地敏感数据必须通过 `AppCryptoService`（AES-256-GCM）加密存储，且遵循 Fail-Closed 原则；
   - 撤回知情同意（`LegalService.revokeAndClearAll()`）必须同步销毁密文缓存、主密钥与双端 WebView 数据；
   - 保持“非官方”定位，严禁使用学校官方校徽。
5. **双端分发约定**：
   - Android：仅构建 `arm64-v8a`（包名 `io.github.korty258.jinhua_assistant`）；
   - Windows：绿色免安装压缩包，固定可执行文件名 `jinhua_assistant.exe`（编辑 `xaut_app/windows/runner/Runner.rc` 时须保持纯 UTF-8 无 BOM）。

---

## 2. 开发环境要求

为与 GitHub Actions CI 保持一致，建议使用以下版本：

- **Flutter**：`3.47.8`（`Dart 3.13.7`）
- **Node.js**：`24.x`（用于运行强智 DOM 解析器回归测试）
- **Java**：JDK 17（如需本地编译 Android APK）

```bash
# 安装 JS 解析测试依赖
cd parser_test && npm ci

# 安装 Flutter 依赖
cd ../xaut_app && flutter pub get
```

---

## 3. 提交前必须通过的本地检查

请在提交 PR 前确保以下全部门禁零错误通过：

```bash
# 1. Node.js 强智解析器回归测试
node --test parser_test/parser.test.js

# 2. Dart 严格静态分析（零 info / warning / error）
dart analyze --fatal-infos xaut_app

# 3. Flutter 全量单测与覆盖率（行覆盖率门禁 >= 80.00%）
cd xaut_app && flutter test --coverage
```

### Widget 测试编写防死锁提示
- 在 `testWidgets`（运行于 `FakeAsync` 沙箱）内，**切勿直接 `await Future.delayed(...)`**；如需等待真实异步 Provider 初始化，请包入 `await tester.runAsync(() async { ... })`，或使用带有限次数上限的 `await tester.pump(...)`。
- 若页面包含持续动画（如 `CircularProgressIndicator`），请使用 `tester.pump()` 或带超时上限的 `tester.pumpAndSettle(...)`。

---

## 4. 分支、Commit 与 PR 流程

1. 从 `main` 切出功能或修复分支（如 `feat/xxx`、`fix/xxx`、`refactor/xxx`）；
2. 推荐使用 [Conventional Commits](https://www.conventionalcommits.org/zh-hans/) 风格编写提交信息（如 `fix: ...`、`feat: ...`、`refactor: ...`、`test: ...`、`docs: ...`）；
3. 切勿提交签名证书（`*.jks`、`*.keystore`、`key.properties`）或包含个人真实学号、密码、真实成绩单 HTML 的测试样本（测试 fixture 请使用匿名合成数据）；
4. 提交 PR 时如实填写 PR 模板中的红线自查与验证结果，等待 GitHub Actions `Lint & Unit Tests` 与双端编译检查全绿后合并。
