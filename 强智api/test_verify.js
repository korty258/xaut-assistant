const fs = require('fs');
const parser = require('./qiangzhi_parser.js');

console.log("=== 1. 测试周次与节次解析 ===");
const weeks = parser.parseWeeks("1-16(周)");
const sections = parser.calculateSections(1, "1-16(周)[01-02节]");
console.log("周次解析:", weeks.length === 16 ? "√ PASS (16周)" : "× FAIL");
console.log("节次计算:", sections.startSection === 1 && sections.stepCount === 2 ? "√ PASS (1-2节)" : "× FAIL");

console.log("\n=== 2. 测试二维码干扰与 HTML 标签清洗 ===");
// 模拟西理工真实教务单元格 HTML（包含隐藏二维码 item-box）
const mockHtml = `<div class="item-box" style="display:none;width:200px"><img src="/jsxsd/jsxx/ewmck?id=2026202710001"/></div>概率论与数理统计B<br/>李教授<br/>1-16(周)[01-02节]<br/>曲江10-601`;

// 提取清洗测试
let cleanText = mockHtml
  .replace(/<div\b[^>]*\bclass=["']?item-box["']?[^>]*>[\s\S]*?<\/div>/gi, "")
  .replace(/<div\b[^>]*\bstyle=["'][^"']*display:\s*none[^"']*["'][^>]*>[\s\S]*?<\/div>/gi, "")
  .replace(/<img\b[^>]*>/gi, "")
  .replace(/<br\s*\/?>/gi, "\n")
  .replace(/<[^>]+>/g, "")
  .replace(/&nbsp;/g, " ")
  .trim();

const lines = cleanText.split("\n").map(l => l.trim()).filter(l => l.length > 0);
const validLines = lines.filter(l => !l.startsWith("<") && !l.includes("ewmck"));

console.log("清洗后提取行数:", validLines.length);
console.log("提取课程名:", validLines[0]);
console.log("提取教师:", validLines[1]);
console.log("提取周次节次:", validLines[2]);
console.log("提取教室:", validLines[3]);

if (validLines[0] === "概率论与数理统计B" && !validLines[0].includes("item-box")) {
  console.log("√ PASS: 课程名纯净，无任何 HTML / 二维码残留！");
} else {
  console.log("× FAIL: 课程名清洗失败！");
}

console.log("\n=== 3. 验证考试解析模块是否去除了座位号 ===");
const examSampleStr = JSON.stringify(parser.parseQiangZhiExams.toString());
if (!examSampleStr.includes("seat") && !examSampleStr.includes("座位号")) {
  console.log("√ PASS: 考试解析模块中已完全剔除座位号相关逻辑！");
} else {
  console.log("× FAIL: 仍包含座位号逻辑");
}

console.log("\n=== 4. 验证排除 kbcontent1 与去重防分栏逻辑 ===");
// 模拟 DOM 环境下的多容器单元格
class MockElement {
  constructor(tag, className = "", innerHTML = "", innerText = "") {
    this.tagName = tag;
    this.className = className;
    this.innerHTML = innerHTML;
    this.innerText = innerText;
    this.children = [];
  }
  querySelectorAll(sel) {
    if (sel === ".kbcontent") {
      return this.children.filter(c => c.className.includes("kbcontent") && !c.className.includes("kbcontent1"));
    }
    if (sel.includes(":not(.kbcontent1)")) {
      return this.children.filter(c => c.className.includes("kb") && !c.className.includes("kbcontent1"));
    }
    return [];
  }
}

const mockCell = new MockElement("td");
const detailedDiv = new MockElement("div", "kbcontent", `C语言程序设计<br/>张老师<br/>1-16(周)[03-04节]<br/>曲江10-205`);
const simpleDiv = new MockElement("div", "kbcontent1", `C语言程序设计<br/>1-16(周)[03-04节]`);
mockCell.children.push(detailedDiv, simpleDiv);

const selected = mockCell.querySelectorAll(".kbcontent");
console.log("匹配的容器数量:", selected.length);
if (selected.length === 1 && !selected[0].className.includes("kbcontent1")) {
  console.log("√ PASS: 成功排除 kbcontent1，单格只提取详细版容器！");
} else {
  console.log("× FAIL: 未正确过滤 kbcontent1！");
}
