## 变更摘要

<!-- 简述本次 PR 解决的问题、核心改动点或关联的 Issue 编号（如 Closes #xx） -->

## 变更类型

- [ ] Bug 修复 (`fix`)
- [ ] 新功能 (`feat`)
- [ ] 重构 / 性能优化 (`refactor` / `perf`)
- [ ] 测试补强 (`test`)
- [ ] 文档 / CI 配置 (`docs` / `chore` / `ci`)

## 业务与隐私合规自查（必选）

- [ ] 未捏造、预留或引入“考场座位号”字段
- [ ] 未引入“冬夏令时”切换逻辑
- [ ] 未引入学业成绩的结构化导出功能
- [ ] 本地敏感数据仍严格经由 `AppCryptoService`（AES-256-GCM）加密存储，且未放宽 `*.xaut.edu.cn` 域名白名单
- [ ] 未包含任何真实个人学号、密码、原始教务 HTML 或签名证书文件；若修改了 `Runner.rc`，已确认保持纯 UTF-8 无 BOM

## 测试与验证结果

- [ ] `node --test parser_test/parser.test.js` 通过
- [ ] `dart analyze --fatal-infos xaut_app` 零告警通过
- [ ] `cd xaut_app && flutter test --coverage` 全部通过（行覆盖率 `>= 65.00%`）

<!-- 如有 UI 改动或窄屏/暗黑模式适配，可附截图或说明 -->
