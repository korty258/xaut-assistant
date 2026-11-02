# 第三方开源声明与致谢 (Third-Party Notices & Acknowledgements)

金花助手（Jinhua Assistant）基于 **GNU General Public License v3.0 (GPL-3.0)** 开放源代码。

本项目在核心架构设计、算法实现与工程探索过程中，参考并借鉴了开源社区中以下优秀开源项目的架构理念与技术经验。我们对这些项目的贡献者深表感谢并完整列出其开源许可与版权声明如下：

---

## 1. Dawn-Course (破晓课程表)

* **项目名称**：Dawn-Course (破晓课程表)
* **上游代码仓库**：[https://github.com/HF-CYGG/Dawn-Course](https://github.com/HF-CYGG/Dawn-Course)
* **开源许可证**：GNU General Public License v3.0 (GPL-3.0)
* **版权所有**：Copyright (C) 2021-2026 HF-CYGG & Dawn-Course Contributors
* **参考范围与声明**：
  金花助手在移动端教学课表布局设计、单节次多课程叠层折叠策略、本周与所有周视图切换算法，以及课程详情弹窗与状态展示的设计模式上，参考了 Dawn-Course 的架构设计思想与用户交互实践。金花助手为基于 Flutter/Dart 的跨平台独立代码实现，未直接复制上游 Kotlin/Compose 源代码。

### 许可证说明与序言 (GPL-3.0，完整条款见根目录 LICENSE)

```text
                    GNU GENERAL PUBLIC LICENSE
                       Version 3, 29 June 2007

 Copyright (C) 2007 Free Software Foundation, Inc. <https://fsf.org/>
 Everyone is permitted to copy and distribute verbatim copies
 of this license document, but changing it is not allowed.

                            Preamble

  The GNU General Public License is a free, copyleft license for
software and other kinds of works.

  The licenses for most software and other practical works are designed
to take away your freedom to share and change the works.  By contrast,
the GNU General Public License is intended to guarantee your freedom to
share and change all versions of a program--to make sure it remains free
software for all its users.  We, the Free Software Foundation, use the
GNU General Public License for most of our software; it applies also to
any other work released this way by its authors.  You can apply it to
your programs, too.

  When we speak of free software, we are referring to freedom, not
price.  Our General Public Licenses are designed to make sure that you
have the freedom to distribute copies of free software (and charge for
them if you wish), that you receive source code or can get it if you
want it, that you can change the software or use pieces of it in new
free programs, and that you know you can do these things.

  To protect your rights, we need to prevent others from denying you
these rights or asking you to surrender the rights.  Therefore, you have
certain responsibilities if you distribute copies of the software, or if
you modify it: responsibilities to respect the freedom of others.

  For example, if you distribute copies of such a program, whether
gratis or for a fee, you must pass on to the recipients the same
freedoms that you received.  You must make sure that they, too, receive
or can get the source code.  And you must show them these terms so they
know their rights.

  Developers that use the GNU GPL protect your rights with two steps:
(1) assert copyright on the software, and (2) offer you this License
giving you legal permission to copy, distribute and/or modify it.

  For the developers' and authors' protection, the GPL clearly explains
that there is no warranty for this free software.  For both users' and
authors' sake, the GPL requires that modified versions be marked as
changed, so that their problems will not be attributed erroneously to
authors of previous versions.

  Some devices are designed to deny users access to install or run
modified versions of the software inside them, although the manufacturer
can do so.  This is fundamentally incompatible with the aim of
protecting users' freedom to change the software.  The systematic
pattern of such abuse occurs in the area of products for individuals to
use, which is precisely where it is most unacceptable.  Therefore, we
have designed this version of the GPL to prohibit the practice for those
products.  If such problems arise substantially in other domains, we
stand ready to extend this provision to those domains in future versions
of the GPL, as needed to protect the freedom of users.

  Finally, every program is threatened constantly by software patents.
States should not allow patents to restrict development and use of
software on general-purpose computers, but in those that do, we wish to
avoid the special danger that patents applied to a free program could
make it effectively proprietary.  To prevent this, the GPL assures that
patents cannot be used to render the program non-free.

  The precise terms and conditions for copying, distribution and
modification are provided in the LICENSE file located at the root of
this repository.
```

---

## 2. NJUST-JWC-Enhance (南理工教务增强助手)

* **项目名称**：NJUST-JWC-Enhance
* **上游代码仓库**：[https://github.com/NJUST-OpenLib/NJUST-JWC-Enhance](https://github.com/NJUST-OpenLib/NJUST-JWC-Enhance)
* **开源许可证**：The MIT License (MIT)
* **版权所有**：Copyright (c) 2021-2026 NJUST-OpenLib & NJUST-JWC-Enhance Contributors
* **参考范围与声明**：
  金花助手在针对湖南强智新学分制系统前端页面 DOM 结构的识别清洗、课表单元格标签文本提取规范、教学周次嗅探推算，以及纯本地无中间服务器解析架构的构建上，参考了 NJUST-JWC-Enhance 的技术经验与解决方案。金花助手解析套件为独立编写的纯本地 JS 脚本。

### 许可证全文 (MIT)

```text
The MIT License (MIT)

Copyright (c) 2021-2026 NJUST-OpenLib & NJUST-JWC-Enhance Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## 3. 金花助手主项目开源许可 (Jinhua Assistant License)

* **软件名称**：金花助手 (Jinhua Assistant)
* **开源许可证**：GNU General Public License v3.0 (GPL-3.0)
* **版权所有**：Copyright (C) 2026 Jinhua Assistant Contributors
* 完整许可证正文请见项目根目录 [LICENSE](LICENSE)。

---

## 4. 核心开源功能组件库 (Core Flutter/Dart Dependencies)

金花助手客户端运行于 Flutter 跨平台框架，依赖以下开源生态组件提供本地运行能力（所有组件均为纯本地运行，不含商业追踪与数据回传）：

| 组件名称 | 许可证类别 | 用途说明 |
| :--- | :--- | :--- |
| **provider** | MIT License | 跨组件响应式状态管理（课表/成绩/考试状态调度） |
| **shared_preferences** | BSD-3-Clause | 本地基础键值对配置与数据持久化 |
| **webview_flutter** | BSD-3-Clause | Android 端内嵌系统官方登录 WebView 容器 |
| **webview_windows** | MIT License | Windows 桌面端 Edge WebView2 运行时嵌入容器 |
| **encrypt** | BSD-3-Clause | AEAD AES-256-GCM 本地全量学业数据信封加密 |
| **flutter_secure_storage** | BSD-3-Clause | 硬件级加密根密钥托管 (Android Keystore / Windows DPAPI) |
| **path_provider** | BSD-3-Clause | 跨平台本地目录与日历文件路径解析 |
| **share_plus** | BSD-3-Clause | 跨平台系统原生分享面板直达系统日历 |
| **flutter_markdown_plus** | BSD-3-Clause | 客户端离线法律合规文档富文本排版渲染 |
| **cupertino_icons** | MIT License | 高清矢量图标资源底座 |

各组件的完整许可证文本与版权声明均内置于应用内「关于与法律条款」-「全量开源组件许可证 (LicensePage)」中，可随时离线查阅。
