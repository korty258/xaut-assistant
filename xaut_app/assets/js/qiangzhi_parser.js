/**
 * 西安理工大学 (XAUT) 强智教务系统 (jsxsd) 完整生产级解析套件
 * 核心升级: 具备自动穿透同源 iframe 能力，无论在主页、内嵌页还是独立页均可一键执行！
 * 修复: 自动清理二维码弹窗 (.item-box / ewmck) 干扰，精准获取纯净课程名！
 * 
 * 模块覆盖:
 *   1. 课表解析 (parseQiangZhiCourses)
 *   2. 成绩解析与绩点学分统计 (parseQiangZhiGrades)
 *   3. 考试安排日程解析 (parseQiangZhiExams)
 */

// ==================== 0. 核心工具: 自动跨 iframe 表格定位 ====================

function findTableAcrossFrames(doc, matcher) {
  if (!doc) doc = document;

  // 1. 先在当前 document 查找
  try {
    const table = matcher(doc);
    if (table) return table;
  } catch (e) {}

  // 2. 递归穿透同源 iframe / frame
  try {
    const iframes = doc.querySelectorAll("iframe, frame");
    for (const frame of iframes) {
      try {
        const subDoc = frame.contentDocument || frame.contentWindow?.document;
        if (subDoc) {
          const subTable = findTableAcrossFrames(subDoc, matcher);
          if (subTable) return subTable;
        }
      } catch (e) {
        // 忽略跨域错误
      }
    }
  } catch (e) {}

  return null;
}


// ==================== 1. 课表解析模块 ====================

function parseQiangZhiCourses(doc = document) {
  const result = [];
  
  // 智能寻找课表 (table#timetable 或 table#kbtable)
  const table = findTableAcrossFrames(doc, d => d.getElementById("timetable") || d.getElementById("kbtable"));
  if (!table) {
    console.error("[-] 未找到课表表格 (#timetable 或 #kbtable)，请确认页面是否已加载课表");
    return result;
  }

  const rows = table.querySelectorAll("tr");
  let sectionIndex = 0;

  for (let r = 0; r < rows.length; r++) {
    const row = rows[r];
    const cells = row.querySelectorAll("td");
    if (cells.length === 0) continue;

    sectionIndex++;
    let startIndex = 0;
    if (cells.length >= 8) {
      startIndex = cells.length - 7;
    }

    for (let c = startIndex; c < cells.length; c++) {
      const dayOfWeek = (c - startIndex) + 1; // 1: 星期一, 7: 星期日
      const cell = cells[c];
      
      // 关键防坑: 强智教务系统每个单元格内部同时存在详细版 .kbcontent 与简略隐藏版 .kbcontent1
      // 必须优先且仅提取 .kbcontent，绝对排除 .kbcontent1，防止同一门课被重复提取为两份并导致分栏折半
      let contents = cell.querySelectorAll(".kbcontent");
      if (contents.length === 0) {
        // 若没有 .kbcontent，降级提取其它非 kbcontent1 的容器
        contents = cell.querySelectorAll("[class*='kb']:not(.kbcontent1)");
      }

      if (contents.length > 0) {
        contents.forEach(kbDiv => {
          extractFromDiv(kbDiv, dayOfWeek, sectionIndex, result);
        });
      } else {
        if (cell.innerText && cell.innerText.trim() && cell.innerText.trim() !== "" && cell.innerText.trim() !== "&nbsp;") {
          extractFromDiv(cell, dayOfWeek, sectionIndex, result);
        }
      }
    }
  }

  // 课程最终智能去重合并：同一天、同节次、同周次的相同课程，优先保留包含教室等完整信息的项
  const deduplicated = [];
  const seen = new Map();

  for (const c of result) {
    if (!c.name || /^[-—_~.\s]+$/.test(c.name)) continue;

    const weekKey = (c.weeks || []).join(",");
    const key = `${c.day}_${c.startSection}_${c.stepCount}_${c.name.trim()}_${weekKey}`;

    if (!seen.has(key)) {
      seen.set(key, c);
      deduplicated.push(c);
    } else {
      const existing = seen.get(key);
      if ((!existing.room || existing.room.trim() === "") && c.room) {
        existing.room = c.room;
      }
      if ((!existing.teacher || existing.teacher.trim() === "") && c.teacher) {
        existing.teacher = c.teacher;
      }
    }
  }

  return deduplicated;
}

function extractFromDiv(kbDiv, dayOfWeek, sectionIndex, result) {
  let rawHtml = "";

  // 1. 如果是真实 DOM 节点，先在克隆节点中彻底移除二维码与隐藏弹窗元素
  if (kbDiv && typeof kbDiv.cloneNode === "function") {
    try {
      const cloned = kbDiv.cloneNode(true);
      const hiddenEls = cloned.querySelectorAll(".item-box, [style*='display:none'], [style*='display: none'], img, script, style");
      hiddenEls.forEach(el => el.remove());
      rawHtml = cloned.innerHTML;
    } catch (e) {
      rawHtml = kbDiv.innerHTML || "";
    }
  } else if (kbDiv) {
    rawHtml = kbDiv.innerHTML || kbDiv.toString() || "";
  }

  if (!rawHtml || !rawHtml.trim() || rawHtml === "&nbsp;") return;

  const courseBlocks = rawHtml.split(/---------------------/g);

  courseBlocks.forEach(block => {
    // 2. 深度清洗 HTML 标签与残留（尤其防范没有闭合标签的片段）
    let cleanText = block
      .replace(/<div\b[^>]*\bclass=["']?item-box["']?[^>]*>[\s\S]*?<\/div>/gi, "")
      .replace(/<div\b[^>]*\bstyle=["'][^"']*display:\s*none[^"']*["'][^>]*>[\s\S]*?<\/div>/gi, "")
      .replace(/<img\b[^>]*>/gi, "")
      .replace(/<br\s*\/?>/gi, "\n")
      .replace(/<[^>]+>/g, "") // 彻底剔除所有剩余 HTML 标签
      .replace(/&nbsp;/g, " ")
      .replace(/&amp;/g, "&")
      .replace(/&lt;/g, "<")
      .replace(/&gt;/g, ">")
      .replace(/\r/g, "")
      .trim();

    if (!cleanText) return;

    const lines = cleanText.split("\n").map(l => l.trim()).filter(l => l.length > 0);
    if (lines.length === 0) return;

    // 过滤掉任何可能残留的 HTML 代码碎片
    const validLines = lines.filter(l => !l.startsWith("<") && !l.includes("ewmck"));
    if (validLines.length === 0) return;

    let courseName = validLines[0] || "未知课程";
    // 过滤纯横杠或无意义占位符（如 "-" 或 "--"）
    if (/^[-—_~.\s]+$/.test(courseName)) return;
    let teacher = "";
    let weeksStr = "";
    let room = "";

    for (let i = 1; i < validLines.length; i++) {
      const line = validLines[i];
      if (/周/.test(line)) {
        weeksStr = line;
      } else if (/(楼|教室|机房|室|馆|场|实验)/.test(line)) {
        room = line;
      } else if (!teacher) {
        teacher = line;
      } else if (!room) {
        room = line;
      }
    }

    const parsedWeeks = parseWeeks(weeksStr);
    const { startSection, stepCount } = calculateSections(sectionIndex, weeksStr);

    result.push({
      name: courseName,
      teacher: teacher,
      room: room,
      day: dayOfWeek,
      startSection: startSection,
      stepCount: stepCount,
      weeks: parsedWeeks,
      rawWeekStr: weeksStr
    });
  });
}

function parseWeeks(weekStr) {
  const weeks = [];
  if (!weekStr) return weeks;

  // 关键防坑: 彻底剔除中括号包含的节次部分（如 [07-08-09-10节] 或 [01-02节]），
  // 避免节次编号（如 07-08、09-10）被全局数字正则误当作上课周次！
  const cleanWeekPart = weekStr.replace(/\[.*?\]/g, "");

  const isOdd = /单/.test(cleanWeekPart);
  const isEven = /双/.test(cleanWeekPart);

  const rangeMatches = cleanWeekPart.matchAll(/(\d+)(?:-(\d+))?/g);
  for (const match of rangeMatches) {
    const start = parseInt(match[1], 10);
    const end = match[2] ? parseInt(match[2], 10) : start;

    for (let w = start; w <= end; w++) {
      if (isOdd && w % 2 === 0) continue;
      if (isEven && w % 2 !== 0) continue;
      if (!weeks.includes(w)) {
        weeks.push(w);
      }
    }
  }

  return weeks.sort((a, b) => a - b);
}

function calculateSections(sectionIndex, weekStr) {
  let startSection = (sectionIndex - 1) * 2 + 1;
  let stepCount = (sectionIndex === 6) ? 3 : 2;

  // 兼容多节连排格式: [01-02节], [07-08-09-10节], [01-04节] 等
  const bracketMatch = weekStr.match(/\[(.*?)节?\]/);
  if (bracketMatch) {
    const nums = bracketMatch[1].match(/\d+/g);
    if (nums && nums.length > 0) {
      const intNums = nums.map(n => parseInt(n, 10));
      const s = Math.min(...intNums);
      const e = Math.max(...intNums);
      startSection = s;
      stepCount = e - s + 1;
    }
  }

  return { startSection, stepCount };
}


// ==================== 2. 成绩查询解析模块 ====================

function parseQiangZhiGrades(doc = document) {
  const grades = [];
  
  // 自动寻找成绩表格（通过 dataList 或表头关键词）
  const table = findTableAcrossFrames(doc, d => {
    return d.getElementById("dataList") || findTableByKeywords(d, ["课程名称", "成绩"]);
  });

  if (!table) {
    console.error("[-] 未找到成绩表格，请确认页面是否已显示成绩数据");
    return { grades, summary: {} };
  }

  const rows = Array.from(table.querySelectorAll("tr"));
  if (rows.length < 2) return { grades, summary: {} };

  const headerCells = Array.from(rows[0].querySelectorAll("th, td")).map(c => c.innerText.trim());
  const colMap = {
    semester: headerCells.findIndex(t => /开课学期|学期/.test(t)),
    courseCode: headerCells.findIndex(t => /课程编号|课程代码/.test(t)),
    courseName: headerCells.findIndex(t => /课程名称/.test(t)),
    score: headerCells.findIndex(t => /^成绩$|综合成绩/.test(t)),
    credit: headerCells.findIndex(t => /学分/.test(t)),
    gpa: headerCells.findIndex(t => /绩点/.test(t)),
    courseCategory: headerCells.findIndex(t => /课程性质|课程属性|选修类别/.test(t)),
    examType: headerCells.findIndex(t => /考核方式|考试性质/.test(t))
  };

  let totalCredits = 0;
  let totalWeightedScore = 0;
  let totalWeightedGpa = 0;

  for (let i = 1; i < rows.length; i++) {
    const cells = Array.from(rows[i].querySelectorAll("td")).map(c => c.innerText.trim());
    if (cells.length < 3) continue;

    const courseName = colMap.courseName !== -1 ? cells[colMap.courseName] : "";
    if (!courseName || courseName === "未查询到数据") continue;

    const scoreStr = colMap.score !== -1 ? cells[colMap.score] : "";
    const credit = colMap.credit !== -1 ? parseFloat(cells[colMap.credit]) || 0 : 0;
    const gpa = colMap.gpa !== -1 ? parseFloat(cells[colMap.gpa]) || 0 : 0;
    const numericScore = parseFloat(scoreStr);

    const gradeItem = {
      semester: colMap.semester !== -1 ? cells[colMap.semester] : "",
      courseCode: colMap.courseCode !== -1 ? cells[colMap.courseCode] : "",
      courseName: courseName,
      score: scoreStr,
      credit: credit,
      gpa: gpa,
      category: colMap.courseCategory !== -1 ? cells[colMap.courseCategory] : "",
      examType: colMap.examType !== -1 ? cells[colMap.examType] : ""
    };

    grades.push(gradeItem);

    if (credit > 0 && !isNaN(numericScore)) {
      totalCredits += credit;
      totalWeightedScore += numericScore * credit;
      if (gpa > 0) {
        totalWeightedGpa += gpa * credit;
      }
    }
  }

  const summary = {
    totalCourses: grades.length,
    totalCredits: parseFloat(totalCredits.toFixed(2)),
    averageScore: totalCredits > 0 ? parseFloat((totalWeightedScore / totalCredits).toFixed(2)) : 0,
    averageGpa: totalCredits > 0 ? parseFloat((totalWeightedGpa / totalCredits).toFixed(2)) : 0
  };

  return { grades, summary };
}


// ==================== 3. 考试安排解析模块 (已去除无用座位号) ====================

function parseQiangZhiExams(doc = document) {
  const exams = [];
  
  // 智能寻找考试表格（支持外层 query 页面或内嵌 list 页面）
  const table = findTableAcrossFrames(doc, d => {
    return d.getElementById("dataList") || findTableByKeywords(d, ["课程名称", "考试时间"]);
  });

  if (!table) {
    console.error("[-] 未找到考试表格，请确认页面是否已显示考试安排数据");
    return exams;
  }

  const rows = Array.from(table.rows);
  if (rows.length < 2) return exams;

  const headerCells = Array.from(rows[0].cells).map(c => c.innerText.trim());
  const colMap = {
    campus: headerCells.findIndex(t => /校区/.test(t)),
    batch: headerCells.findIndex(t => /场次|批次/.test(t)),
    courseCode: headerCells.findIndex(t => /课程编号|课程代码/.test(t)),
    courseName: headerCells.findIndex(t => /课程名称/.test(t)),
    teacher: headerCells.findIndex(t => /教师/.test(t)),
    examTime: headerCells.findIndex(t => /考试时间/.test(t)),
    room: headerCells.findIndex(t => /考场|地点/.test(t))
  };

  for (let i = 1; i < rows.length; i++) {
    const cells = Array.from(rows[i].cells).map(c => c.innerText.trim());
    if (cells.length < 4) continue;

    const courseName = colMap.courseName !== -1 ? cells[colMap.courseName] : "";
    if (!courseName || courseName === "未查询到数据") continue;

    exams.push({
      campus: colMap.campus !== -1 ? cells[colMap.campus] : "",
      batch: colMap.batch !== -1 ? cells[colMap.batch] : "",
      courseCode: colMap.courseCode !== -1 ? cells[colMap.courseCode] : "",
      courseName: courseName,
      teacher: colMap.teacher !== -1 ? cells[colMap.teacher] : "",
      examTime: colMap.examTime !== -1 ? cells[colMap.examTime] : "",
      room: colMap.room !== -1 ? cells[colMap.room] : ""
    });
  }

  return exams;
}


// ==================== 辅助关键字匹配 ====================

function findTableByKeywords(doc, keywords) {
  const tables = doc.querySelectorAll("table");
  for (const t of tables) {
    const text = t.innerText || "";
    if (keywords.every(kw => text.includes(kw))) {
      return t;
    }
  }
  return null;
}

// 导出模块 (兼容 Node 与 浏览器)
if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    parseQiangZhiCourses,
    parseWeeks,
    calculateSections,
    parseQiangZhiGrades,
    parseQiangZhiExams
  };
}
