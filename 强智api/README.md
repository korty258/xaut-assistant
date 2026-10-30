# 西安理工大学 (XAUT) 强智教务系统 API 调研与开发指南 (v1.0.0-verified)

本文档结合了以下两个开源项目的思路：
1. **[Dawn-Course (破晓课程表)](https://github.com/HF-CYGG/Dawn-Course)**：现代 Android 课程表架构，采用 **WebView 登录鉴权 + JS 解析脚本注入** 模式，轻量且容错率极高。
2. **[NJUST-JWC-Enhance (南理工教务系统增强)](https://github.com/NJUST-OpenLib/NJUST-JWC-Enhance)**：深度适配强智教务系统（`jsxsd` 架构），包含 DOM 解析、自动评教、学分统计与 Session 保活机制。

---

## 一、系统实测特征分析

* **教务网址**：`https://jwgl.xaut.edu.cn/`（强智系统核心路由：`/jsxsd/`）
* **系统类型**：湖南强智科技（QZDataSoft）新学分制教务管理系统
* **统一认证中心**：`https://ids.xaut.edu.cn/authserver/login`（金智 Wisedu CAS 认证）
* **快照版本**：`v1.0.0-verified`（所有核心模块均已 100% 实测跑通）

---

## 二、实测打通的业务模块清单

| 模块名称 | 真实路径 | 核心特征 / 关键节点 | 适配处理 |
| :--- | :--- | :--- | :--- |
| **课表查询** | `/jsxsd/xskb/xskb_list.do` | `table#timetable`<br>课程容器：`.kbcontent`<br>多课分隔：`---------------------` | 提取课程、教师、教室、星期、节次；自适应单双周及多周区间解析。 |
| **成绩查询** | `/jsxsd/kscj/cjcx_list` | `table#dataList`<br>包含分数、学分、绩点 | 自适应表头定位；自动计算总学分、加权平均分与平均 GPA。 |
| **考试安排** | `/jsxsd/xsks/xsksap_query`<br>*(内嵌 `/jsxsd/xsks/xsksap_list`)* | `table#dataList`<br>类名 `.layui-table`<br>参数：`xnxqid` | 内置 `findTableAcrossFrames` 自动穿透子 iframe 提取考场、座位号、倒计时时间。 |

---

## 三、文件资产与结构

* **`qiangzhi_parser.js`**：生产级全功能解析脚本（课表 `parseQiangZhiCourses`、成绩 `parseQiangZhiGrades`、考试 `parseQiangZhiExams`），内置跨 iframe 定位能力。
* **`test_parser.js`**：Node.js 离线单元测试脚本。
* **`test_sample_schedule.html`**：离线测试课表 HTML 样本。
* **`qiangzhi_probe.py`**：移动端 `/app.do` 原生接口探测工具。
* **`qiangzhi_web_client.py`**：Python Web 模拟请求与离线抓取模板。

---

## 四、Git 快照记录

本目录已初始化 Git 仓库并完成稳定标签锁定：
* **Commit**：`62fdfb3`
* **Tag**：`v1.0.0-verified`
* 若后续代码调试需要恢复，可随时执行：
  ```bash
  git checkout v1.0.0-verified
  ```
