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

    // 关键防坑 1: 忽略表尾的备注/实践教学环节/未排时间课程等汇总说明行
    const rowText = (row.innerText || "").trim();
    if (/^(备注|实践环节|实践教学|未排时间|调课)/.test(rowText) || rowText.includes("实践教学环节") || (rowText.includes(";") && rowText.includes("周"))) {
      continue;
    }
    const hasBroadColspan = Array.from(cells).some(td => (parseInt(td.getAttribute("colspan") || "1", 10) >= 5));
    if (hasBroadColspan && cells.length <= 3) {
      continue;
    }

    // 关键防坑 2: 西安理工大学官方每日至多 6 个大节 (1-2, 3-4, 5-6, 7-8, 9-10, 11-13)，节次索引绝不能超过 6！
    if (sectionIndex >= 6) {
      break;
    }

    sectionIndex++;
    let startIndex = 0;
    if (cells.length >= 8) {
      startIndex = cells.length - 7;
    }

    for (let c = startIndex; c < cells.length; c++) {
      const dayOfWeek = (c - startIndex) + 1; // 1: 星期一, 7: 星期日
      if (dayOfWeek > 7) break;
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
          const t = cell.innerText.trim();
          // 只有具备常规课表格式且非分号拼接的备注时才尝试降级提取
          if (!t.includes(";") && !/^(备注|实践)/.test(t)) {
            extractFromDiv(cell, dayOfWeek, sectionIndex, result);
          }
        }
      }
    }
  }

  // 课程最终智能去重合并：同一天、同节次、同周次的相同课程，优先保留包含教室等完整信息的项
  const deduplicated = [];
  const seen = new Map();

  for (const c of result) {
    if (!c.name || /^[-—_~.\s]+$/.test(c.name)) continue;
    // 彻底剔除伪课程（包含分号拼接多门课或节次超出 13 小节）
    if (c.name.includes(";") && (c.name.includes("周") || c.name.includes("实验") || c.name.includes("训练"))) continue;
    if (c.startSection > 13 || c.day < 1 || c.day > 7) continue;
    if (!c.weeks || c.weeks.length === 0) continue;

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

    // 关键过滤：若课程名中包含分号且包含周次 (如 "工程训练 B 夏春莉 7-15周;工程训练 B...")，属于强智底部表格备注误入，严禁当作单门课程解析
    if (courseName.includes(";") && (courseName.includes("周") || courseName.includes("实验") || courseName.includes("训练"))) return;
    if (/^(备注|实践教学|实践环节|未排时间)/.test(courseName)) return;

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
    // 过滤无有效周次的异常条目
    if (parsedWeeks.length === 0 && (!weeksStr || !weeksStr.includes("周"))) return;

    const { startSection, stepCount } = calculateSections(sectionIndex, weeksStr);
    if (startSection > 13) return;

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
  let scoreCredits = 0;
  let gpaCredits = 0;
  let totalWeightedScore = 0;
  let totalWeightedGpa = 0;

  const levelMap = {
    "优": { score: 95, gpa: 4.5, gpaCourse: true },
    "优秀": { score: 95, gpa: 4.5, gpaCourse: true },
    "良": { score: 85, gpa: 3.5, gpaCourse: true },
    "良好": { score: 85, gpa: 3.5, gpaCourse: true },
    "中": { score: 75, gpa: 2.5, gpaCourse: true },
    "中等": { score: 75, gpa: 2.5, gpaCourse: true },
    "及格": { score: 65, gpa: 1.5, gpaCourse: true },
    "不及格": { score: 50, gpa: 0, gpaCourse: true }
  };

  for (let i = 1; i < rows.length; i++) {
    const cells = Array.from(rows[i].querySelectorAll("td")).map(c => c.innerText.trim());
    if (cells.length < 3) continue;

    const courseName = colMap.courseName !== -1 ? cells[colMap.courseName] : "";
    if (!courseName || courseName === "未查询到数据") continue;

    const scoreStr = (colMap.score !== -1 ? cells[colMap.score] : "").trim();
    const credit = colMap.credit !== -1 ? parseFloat(cells[colMap.credit]) || 0 : 0;
    const gpa = colMap.gpa !== -1 ? parseFloat(cells[colMap.gpa]) || 0 : 0;
    const numericScore = Number(scoreStr !== "" ? scoreStr : NaN);

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

    if (credit > 0 && scoreStr && !/^(缓考|缺考|免考)$/.test(scoreStr)) {
      totalCredits += credit;

      if (!isNaN(numericScore)) {
        scoreCredits += credit;
        totalWeightedScore += numericScore * credit;
        const effGpa = gpa > 0 ? gpa : (numericScore >= 60 ? (numericScore - 50) / 10 : 0);
        gpaCredits += credit;
        totalWeightedGpa += effGpa * credit;
      } else if (levelMap[scoreStr]) {
        const lv = levelMap[scoreStr];
        scoreCredits += credit;
        totalWeightedScore += lv.score * credit;
        const effGpa = gpa > 0 ? gpa : lv.gpa;
        gpaCredits += credit;
        totalWeightedGpa += effGpa * credit;
      } else if (gpa > 0) {
        // 合格/通过等二级制或其它带有明确绩点的课程
        gpaCredits += credit;
        totalWeightedGpa += gpa * credit;
      }
    }
  }

  const summary = {
    totalCourses: grades.length,
    totalCredits: parseFloat(totalCredits.toFixed(2)),
    averageScore: scoreCredits > 0 ? parseFloat((totalWeightedScore / scoreCredits).toFixed(2)) : 0,
    averageGpa: gpaCredits > 0 ? parseFloat((totalWeightedGpa / gpaCredits).toFixed(2)) : 0
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

// ==================== 4. 当前教学周与学期基准自动识别模块 ====================

function collectDocsAcrossFrames(doc) {
  const docs = [];
  function walk(d) {
    if (!d || docs.includes(d)) return;
    docs.push(d);
    try {
      const iframes = d.querySelectorAll("iframe, frame");
      for (const frame of iframes) {
        try {
          const subDoc = frame.contentDocument || frame.contentWindow?.document;
          if (subDoc) walk(subDoc);
        } catch (e) {}
      }
    } catch (e) {}
  }
  walk(doc || (typeof document !== "undefined" ? document : null));
  return docs;
}

function parseQiangZhiTeachingWeek(doc = document, allowSelectFallback = true) {
  const info = {
    currentWeek: null,
    semester: "",
    semesterStartDate: ""
  };

  const docs = collectDocsAcrossFrames(doc);
  const noticeBlacklist = /(通知|公告|选课|调课|停课|缓考|补考|考试|讲座|报名|重修|评教)/;

  // 1. 最高优先级：顶部状态栏「2026-2027-1 第9周」或「2026-2027学年第一学期 第9周」
  for (const d of docs) {
    try {
      const candidates = d.querySelectorAll("span, div, li, a, p, em, strong, b, td");
      for (const el of candidates) {
        if (el.children && el.children.length > 5) continue;
        if (typeof el.closest === "function" && el.closest("#timetable, #kbtable, #dataList, .kbcontent, .kbcontent1")) {
          continue;
        }
        const txt = (el.textContent || "").replace(/\s+/g, " ").trim();
        if (!txt || txt.length > 55 || noticeBlacklist.test(txt)) continue;

        const mSem = txt.match(/(\d{4}-\d{4}-[12])\s*第\s*(\d{1,2})\s*周(?![\d\-~,，])/);
        if (mSem) {
          const w = parseInt(mSem[2], 10);
          if (w >= 1 && w <= 30) {
            info.semester = mSem[1];
            info.currentWeek = w;
            return info;
          }
        }

        const mCn = txt.match(/(\d{4}-\d{4}学年[^第\n]{0,12})\s*第\s*(\d{1,2})\s*周(?![\d\-~,，])/);
        if (mCn) {
          const w = parseInt(mCn[2], 10);
          if (w >= 1 && w <= 30) {
            info.semester = mCn[1].trim();
            info.currentWeek = w;
            return info;
          }
        }
      }
    } catch (e) {}
  }

  // 2. 次高优先级：强智顶栏专用周次容器 (#li_showWeek 等)
  for (const d of docs) {
    try {
      const weekEls = d.querySelectorAll("#li_showWeek, #showWeek, .top_week, .main_week, .header_week, [id*='showWeek']");
      for (const el of weekEls) {
        const txt = (el.textContent || "").replace(/\s+/g, " ").trim();
        if (!txt || txt.length > 60 || noticeBlacklist.test(txt)) continue;
        const m = txt.match(/第\s*(\d{1,2})\s*周(?![\d\-~,，])/);
        if (m) {
          const w = parseInt(m[1], 10);
          if (w >= 1 && w <= 30) {
            info.currentWeek = w;
            break;
          }
        }
      }
      if (info.currentWeek) break;
    } catch (e) {}
  }

  // 3. 门户主页「我的桌面 -> 我的课表」默认选中周次下拉框（如 "第9周"）
  if (!info.currentWeek && allowSelectFallback) {
    for (const d of docs) {
      try {
        // 标准 <select>
        const selects = d.querySelectorAll("select");
        for (const sel of selects) {
          const selectedOpt =
            (typeof sel.selectedIndex === "number" && sel.selectedIndex >= 0 && sel.options
              ? sel.options[sel.selectedIndex]
              : null) || sel.querySelector("option[selected]");
          if (selectedOpt) {
            const optTxt = (selectedOpt.textContent || "").trim();
            const m = optTxt.match(/^第\s*(\d{1,2})\s*周$/);
            if (m) {
              const w = parseInt(m[1], 10);
              if (w >= 1 && w <= 30) {
                info.currentWeek = w;
                break;
              }
            }
          }
        }
        if (info.currentWeek) break;

        // Layui 渲染下拉框
        const layuiSelected = d.querySelectorAll(".layui-form-select .layui-select-title input, .layui-form-select dl dd.layui-this");
        for (const item of layuiSelected) {
          const val = ((item.value !== undefined ? item.value : item.textContent) || "").trim();
          const m = val.match(/^第\s*(\d{1,2})\s*周$/);
          if (m) {
            const w = parseInt(m[1], 10);
            if (w >= 1 && w <= 30) {
              info.currentWeek = w;
              break;
            }
          }
        }
        if (info.currentWeek) break;
      } catch (e) {}
    }
  }

  // 4. 补充提取当前学年学期标识 (如 2026-2027-1)
  if (!info.semester) {
    for (const d of docs) {
      try {
        const semSel = d.querySelector("select[name='xnxq01id'], select[name='xnxqid'], #xnxq01id, #xnxqid");
        if (semSel) {
          const opt =
            (typeof semSel.selectedIndex === "number" && semSel.selectedIndex >= 0 && semSel.options
              ? semSel.options[semSel.selectedIndex]
              : null) || semSel.querySelector("option[selected]");
          if (opt) {
            const v = (opt.value || opt.textContent || "").trim();
            if (/^\d{4}-\d{4}-[12]$/.test(v)) {
              info.semester = v;
              break;
            }
          }
        }
      } catch (e) {}
    }
  }

  return info;
}

function parseQiangZhiCalendarStart(doc = document) {
  if (!doc) return "";
  try {
    const rows = doc.querySelectorAll("tr");
    for (const row of rows) {
      const cells = row.querySelectorAll("td, th");
      if (cells.length < 7) continue;
      const firstTxt = (cells[0].textContent || "").replace(/\s+/g, "").trim();
      if (firstTxt === "1" || firstTxt === "01" || firstTxt === "第1周" || firstTxt === "第一周") {
        for (let i = 1; i < cells.length; i++) {
          const attrText = (cells[i].getAttribute("title") || "") + " " + (cells[i].getAttribute("val") || "") + " " + (cells[i].textContent || "");
          const m = attrText.match(/(\d{4})[-年\/](\d{1,2})[-月\/](\d{1,2})/);
          if (m) {
            const y = m[1];
            const mo = m[2].padStart(2, "0");
            const da = m[3].padStart(2, "0");
            return `${y}-${mo}-${da}`;
          }
        }
      }
    }
  } catch (e) {}
  return "";
}

// 导出模块 (兼容 Node 与 浏览器)
if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    parseQiangZhiCourses,
    parseWeeks,
    calculateSections,
    parseQiangZhiGrades,
    parseQiangZhiExams,
    parseQiangZhiTeachingWeek,
    parseQiangZhiCalendarStart
  };
}
