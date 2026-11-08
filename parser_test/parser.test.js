const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('jsdom');

// 引入被测解析器生产套件
const parser = require('../xaut_app/assets/js/qiangzhi_parser.js');

function loadDomFixture(filename) {
  const filePath = path.join(__dirname, 'fixtures', filename);
  const html = fs.readFileSync(filePath, 'utf8');
  const dom = new JSDOM(html, { url: 'https://jwgl.xaut.edu.cn/jsxsd/' });
  return dom.window.document;
}

test('1. 课表解析回归测试 (parseQiangZhiCourses)', async (t) => {
  await t.test('完整样本 (timetable_full.html) 能够正确提取课程、连排及过滤伪课程', () => {
    const doc = loadDomFixture('timetable_full.html');
    const courses = parser.parseQiangZhiCourses(doc);

    // 应该严格解析出 6 门有效课程
    assert.equal(courses.length, 6, `预期 6 门课程，实际解析到 ${courses.length} 门`);

    // 1. 高等数学(上) - 星期一 1-2 节
    const math = courses.find(c => c.name === '高等数学(上)');
    assert.ok(math, '未能找到高等数学(上)');
    assert.equal(math.day, 1);
    assert.equal(math.startSection, 1);
    assert.equal(math.stepCount, 2);
    assert.equal(math.teacher, '张老师');
    assert.equal(math.room, '教1-301');
    assert.deepEqual(math.weeks, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]);

    // 2. 单双周叠排测试 - 星期三 1-2 节
    const physics = courses.find(c => c.name === '大学物理(一)');
    assert.ok(physics, '未能找到大学物理(一)');
    assert.equal(physics.day, 3);
    assert.equal(physics.startSection, 1);
    assert.equal(physics.stepCount, 2);
    assert.deepEqual(physics.weeks, [1, 3, 5, 7, 9, 11, 13, 15]);

    const english = courses.find(c => c.name === '大学英语(三)');
    assert.ok(english, '未能找到大学英语(三)');
    assert.equal(english.day, 3);
    assert.equal(english.startSection, 1);
    assert.equal(english.stepCount, 2);
    assert.deepEqual(english.weeks, [2, 4, 6, 8, 10, 12, 14, 16]);

    // 3. 4 节连排测试 - 星期四 7-10 节 [07-08-09-10节]
    const circuit = courses.find(c => c.name === '电路基础实验');
    assert.ok(circuit, '未能找到电路基础实验');
    assert.equal(circuit.day, 4);
    assert.equal(circuit.startSection, 7);
    assert.equal(circuit.stepCount, 4); // 验证 4 节连排
    assert.deepEqual(circuit.weeks, [15, 16]); // 验证节次 7-10 未被误当作周次

    // 4. 晚间第 6 大节测试 - 星期五 11-13 节 (3 小节)
    const policy = courses.find(c => c.name === '形势与政策');
    assert.ok(policy, '未能找到形势与政策');
    assert.equal(policy.day, 5);
    assert.equal(policy.startSection, 11);
    assert.equal(policy.stepCount, 3);
    assert.deepEqual(policy.weeks, [1, 2, 3, 4, 5, 6, 7, 8]);

    // 5. 校验防坑点：
    // - .kbcontent1 简版未被提取导致重复
    const mathCount = courses.filter(c => c.name === '高等数学(上)').length;
    assert.equal(mathCount, 1, '高等数学(上) 不应出现重复记录');

    // - 二维码 .item-box 未残留
    const hasEwmck = courses.some(c => JSON.stringify(c).includes('ewmck'));
    assert.equal(hasEwmck, false, '二维码残留不应出现在解析结果中');

    // - 表尾实践教学环节/备注未误入伪课程
    const hasRemark = courses.some(c => c.name.includes('金工实习') || c.name.includes('备注'));
    assert.equal(hasRemark, false, '表尾备注/未排时间课程不应作为课表条目提取');
  });

  await t.test('空白样本 (timetable_empty.html) 返回空数组', () => {
    const doc = loadDomFixture('timetable_empty.html');
    const courses = parser.parseQiangZhiCourses(doc);
    assert.deepEqual(courses, []);
  });

  await t.test('登录页负例 (login_page.html) 返回空数组且不抛出异常', () => {
    const doc = loadDomFixture('login_page.html');
    const courses = parser.parseQiangZhiCourses(doc);
    assert.deepEqual(courses, []);
  });
});

test('2. 成绩解析回归测试 (parseQiangZhiGrades)', async (t) => {
  await t.test('混合制样本 (grades_mixed.html) 能够正确折算五级/二级制与 GPA', () => {
    const doc = loadDomFixture('grades_mixed.html');
    const result = parser.parseQiangZhiGrades(doc);

    assert.ok(result.grades, 'grades 字段应存在');
    assert.equal(result.grades.length, 6, '应解析出 6 条成绩记录');

    // 缓考不计入加权，有效学分 = 4 + 3 + 3 + 1 + 2 = 13.0
    assert.equal(result.summary.totalCourses, 6);
    assert.equal(result.summary.totalCredits, 13.0);
    // 加权平均分 = (88*4 + 95*3 + 85*3 + 65*1) / 11 = 957 / 11 = 87.0
    assert.equal(result.summary.averageScore, 87.0);
    // 加权平均 GPA = (3.8*4 + 4.5*3 + 3.5*3 + 1.5*1) / 11 = 40.7 / 11 = 3.7
    assert.equal(result.summary.averageGpa, 3.7);
  });

  await t.test('登录页负例 (login_page.html) 返回空成绩与空统计', () => {
    const doc = loadDomFixture('login_page.html');
    const result = parser.parseQiangZhiGrades(doc);
    assert.deepEqual(result.grades, []);
    assert.deepEqual(result.summary, {});
  });
});

test('3. 考试安排解析回归测试 (parseQiangZhiExams)', async (t) => {
  await t.test('考试列表样本 (exams_list.html) 正确提取，且绝对不包含座位号', () => {
    const doc = loadDomFixture('exams_list.html');
    const exams = parser.parseQiangZhiExams(doc);

    assert.equal(exams.length, 2);
    assert.equal(exams[0].courseName, '高等数学(上)');
    assert.equal(exams[0].campus, '金花校区');
    assert.equal(exams[0].room, '教1-201');
    assert.equal(exams[0].examTime, '2026-12-25 09:00-11:00');

    // 红线校验：绝不可输出 seat / 座位号
    for (const exam of exams) {
      assert.equal(exam.seat, undefined);
      assert.equal(exam.seatNumber, undefined);
      assert.equal(exam.zwh, undefined);
    }
  });

  await t.test('登录页负例 (login_page.html) 返回空考试列表', () => {
    const doc = loadDomFixture('login_page.html');
    const exams = parser.parseQiangZhiExams(doc);
    assert.deepEqual(exams, []);
  });

  await t.test('外层布局 table 嵌套与带前置横幅行的考试表格正确解析', () => {
    const html = `
      <!DOCTYPE html><html><body>
        <table width="100%">
          <tr><td>查询条件：课程名称 / 考试时间</td></tr>
          <tr><td>
            <table id="dataList">
              <tr><td colspan="7">2026-2027-1 学生考试安排表</td></tr>
              <tr>
                <th>序号</th><th>校区</th><th>考试场次</th><th>课程代码</th>
                <th>考试课程</th><th>授课教师</th><th>监考教师</th><th>考试时间</th><th>教室</th>
              </tr>
              <tr>
                <td>1</td><td>金花校区</td><td>期末第1场</td><td>CS201</td>
                <td>数据结构</td><td>王老师</td><td>赵老师</td><td>2027-01-05 09:00-11:00</td><td>教2-305</td>
              </tr>
            </table>
          </td></tr>
        </table>
      </body></html>
    `;
    const dom = new JSDOM(html, { url: 'https://jwgl.xaut.edu.cn/jsxsd/xsks/xsksap_list' });
    const exams = parser.parseQiangZhiExams(dom.window.document);
    assert.equal(exams.length, 1);
    assert.equal(exams[0].courseName, '数据结构');
    assert.equal(exams[0].teacher, '王老师');
    assert.equal(exams[0].room, '教2-305');
  });
});

test('4. 教学周与学期识别回归测试 (parseQiangZhiTeachingWeek)', async (t) => {
  await t.test('首页顶栏样本 (home_week_banner.html) 正确识别周次与学期', () => {
    const doc = loadDomFixture('home_week_banner.html');
    const weekInfo = parser.parseQiangZhiTeachingWeek(doc);

    assert.equal(weekInfo.currentWeek, 9);
    assert.equal(weekInfo.semester, '2026-2027-1');
  });

  await t.test('学期下拉框含前置空选项 "---请选择---" 时仍能正确识别 option[selected]', () => {
    const html = `
      <!DOCTYPE html><html><body>
        <select name="xqlbmc"><option value="" selected="selected">---请选择---</option></select>
        <select id="xnxq01id" name="xnxq01id">
          <option value="">---请选择---</option>
          <option value="2026-2027-1" selected="selected">2026-2027-1</option>
        </select>
      </body></html>
    `;
    const dom = new JSDOM(html, { url: 'https://jwgl.xaut.edu.cn/jsxsd/xskb/xskb_list.do' });
    const weekInfo = parser.parseQiangZhiTeachingWeek(dom.window.document, false);
    assert.equal(weekInfo.semester, '2026-2027-1');
  });

  await t.test('登录页负例 (login_page.html) 周次为 null 且不抛出异常', () => {
    const doc = loadDomFixture('login_page.html');
    const weekInfo = parser.parseQiangZhiTeachingWeek(doc);

    assert.equal(weekInfo.currentWeek, null);
    assert.equal(weekInfo.semester, '');
  });
});

test('5. 复杂周次解析回归测试 (parseWeeks)', async (t) => {
  await t.test('混合单双周格式: "1-4单周,5-8周"', () => {
    assert.deepEqual(parser.parseWeeks('1-4单周,5-8周'), [1, 3, 5, 6, 7, 8]);
  });

  await t.test('前导无修饰继承末尾单周: "1-3,5-7单周"', () => {
    assert.deepEqual(parser.parseWeeks('1-3,5-7单周'), [1, 3, 5, 7]);
  });

  await t.test('前后不同单双周: "1-8单周,9-16双周"', () => {
    assert.deepEqual(parser.parseWeeks('1-8单周,9-16双周'), [1, 3, 5, 7, 10, 12, 14, 16]);
  });

  await t.test('含节次中括号混入: "1-4单周,5-8周[01-02节]"', () => {
    assert.deepEqual(parser.parseWeeks('1-4单周,5-8周[01-02节]'), [1, 3, 5, 6, 7, 8]);
  });
});

test('6. 考试异步拉取状态机回归测试 (fetchExamScheduleAsync)', async (t) => {
  const dartFilePath = path.join(__dirname, '../xaut_app/lib/services/parser_service.dart');
  const dartCode = fs.readFileSync(dartFilePath, 'utf8');
  const helperMatch = dartCode.match(/static String _buildAsyncBridgeHelperJs[\s\S]*?return '''([\s\S]*?)''';/);
  assert.ok(helperMatch, '未能从 parser_service.dart 提取 _buildAsyncBridgeHelperJs');

  const parserJsPath = path.join(__dirname, '../xaut_app/assets/js/qiangzhi_parser.js');
  const parserJsCode = fs.readFileSync(parserJsPath, 'utf8');

  function setupSandbox({ currentUrl = 'https://jwgl.xaut.edu.cn/jsxsd/framework/xsMain.html', documentHtml = '<!DOCTYPE html><html><body></body></html>', fetchHandler } = {}) {
    const dom = new JSDOM(documentHtml, {
      url: currentUrl,
      runScripts: 'dangerously',
    });
    const win = dom.window;

    win.fetch = async (url, init = {}) => {
      if (fetchHandler) {
        return fetchHandler(url, init);
      }
      return { ok: false, status: 500, text: async () => '' };
    };

    win.eval(parserJsCode);

    let helperJs = helperMatch[1]
      .replace(/\$safeRequestId/g, '"test_req_exam"')
      .replace(/\$timeoutMs/g, '30000')
      .replace(/\\\$/g, '$');

    helperJs += '\nwindow.fetchExamScheduleAsync = fetchExamScheduleAsync;';
    win.eval(helperJs);

    return { win, dom };
  }

  await t.test('场景1: 查询页返回含空 #dataList 表壳，后续 xsksap_list 网络全部失败 -> status 必须为 error 并保留缓存', async () => {
    const queryHtmlWithEmptyShell = `
      <!DOCTYPE html><html><body>
        <select name="xnxqid"><option value="2026-2027-1" selected>2026-2027-1</option></select>
        <table id="dataList"></table>
      </body></html>
    `;
    const { win } = setupSandbox({
      fetchHandler: async (url, init) => {
        if (url.includes('/jsxsd/xsks/xsksap_query')) {
          return { ok: true, status: 200, text: async () => queryHtmlWithEmptyShell };
        }
        return { ok: false, status: 500, text: async () => '' };
      }
    });

    const res = await win.fetchExamScheduleAsync('', [], 'https://jwgl.xaut.edu.cn/jsxsd/framework/xsMain.html');
    assert.equal(res.status, 'error');
    assert.equal(res.exams.length, 0);
    assert.ok(res.error && res.error.includes('考试安排网络请求失败'));
  });

  await t.test('场景2: 当前页存在空 #dataList 表壳，网络兜底全部失败 -> status 必须为 error 绝不误判 empty', async () => {
    const currentDocHtml = `
      <!DOCTYPE html><html><body>
        <table id="dataList"></table>
      </body></html>
    `;
    const { win } = setupSandbox({
      currentUrl: 'https://jwgl.xaut.edu.cn/jsxsd/xsks/xsksap_query',
      documentHtml: currentDocHtml,
      fetchHandler: async (url, init) => {
        return { ok: false, status: 502, text: async () => '' };
      }
    });

    const res = await win.fetchExamScheduleAsync('', [], 'https://jwgl.xaut.edu.cn/jsxsd/xsks/xsksap_query');
    assert.equal(res.status, 'error');
    assert.equal(res.exams.length, 0);
    assert.ok(res.error && res.error.includes('考试安排网络请求失败'));
  });

  await t.test('场景3: 查询页与权威列表页均成功，且列表页返回合法表头但无记录的空表 -> status 为 empty', async () => {
    const queryHtml = `
      <!DOCTYPE html><html><body>
        <select name="xnxqid"><option value="2026-2027-1" selected>2026-2027-1</option></select>
      </body></html>
    `;
    const authoritativeEmptyListHtml = `
      <!DOCTYPE html><html><body>
        <table id="dataList">
          <tr><th>序号</th><th>校区</th><th>课程名称</th><th>考试时间</th><th>考场</th></tr>
        </table>
      </body></html>
    `;
    const { win } = setupSandbox({
      fetchHandler: async (url, init) => {
        if (url.includes('/jsxsd/xsks/xsksap_query')) {
          return { ok: true, status: 200, text: async () => queryHtml };
        }
        if (url.includes('/jsxsd/xsks/xsksap_list')) {
          return { ok: true, status: 200, text: async () => authoritativeEmptyListHtml };
        }
        return { ok: false, status: 404, text: async () => '' };
      }
    });

    const res = await win.fetchExamScheduleAsync('', [], 'https://jwgl.xaut.edu.cn/jsxsd/framework/xsMain.html');
    assert.equal(res.status, 'empty');
    assert.equal(res.exams.length, 0);
    assert.equal(res.error, null);
  });

  await t.test('场景4: 第一个候选学期失败但第二个候选学期成功返回数据 -> status 成功 ok 且不被前序失败掩盖', async () => {
    const queryHtml = `
      <!DOCTYPE html><html><body>
        <select name="xnxqid"><option value="2026-2027-1" selected>2026-2027-1</option></select>
      </body></html>
    `;
    const validExamsHtml = `
      <!DOCTYPE html><html><body>
        <table id="dataList">
          <tr><th>序号</th><th>校区</th><th>课程名称</th><th>考试时间</th><th>考场</th></tr>
          <tr><td>1</td><td>金花校区</td><td>大学物理</td><td>2027-01-10 09:00-11:00</td><td>教1-101</td></tr>
        </table>
      </body></html>
    `;
    const { win } = setupSandbox({
      fetchHandler: async (url, init) => {
        if (url.includes('/jsxsd/xsks/xsksap_query')) {
          return { ok: true, status: 200, text: async () => queryHtml };
        }
        if (url.includes('2026-2027-1') || (init.body && init.body.includes('2026-2027-1'))) {
          return { ok: false, status: 500, text: async () => '' };
        }
        if (url.includes('2025-2026-2') || (init.body && init.body.includes('2025-2026-2'))) {
          return { ok: true, status: 200, text: async () => validExamsHtml };
        }
        return { ok: false, status: 404, text: async () => '' };
      }
    });

    const res = await win.fetchExamScheduleAsync('2025-2026-2', [], 'https://jwgl.xaut.edu.cn/jsxsd/framework/xsMain.html');
    assert.equal(res.status, 'ok');
    assert.equal(res.exams.length, 1);
    assert.equal(res.exams[0].courseName, '大学物理');
    assert.equal(res.error, null);
  });

  await t.test('场景5: 所有候选学期均无数据，但存在一次传输失败 -> 必须返回 error 严防弱网误清空缓存', async () => {
    const queryHtml = `
      <!DOCTYPE html><html><body>
        <select name="xnxqid"><option value="2026-2027-1" selected>2026-2027-1</option></select>
      </body></html>
    `;
    const authoritativeEmptyListHtml = `
      <!DOCTYPE html><html><body>
        <table id="dataList">
          <tr><th>序号</th><th>校区</th><th>课程名称</th><th>考试时间</th><th>考场</th></tr>
        </table>
      </body></html>
    `;
    const { win } = setupSandbox({
      fetchHandler: async (url, init) => {
        if (url.includes('/jsxsd/xsks/xsksap_query')) {
          return { ok: true, status: 200, text: async () => queryHtml };
        }
        if (init.method === 'GET' && url.includes('2026-2027-1')) {
          return { ok: false, status: 504, text: async () => '' };
        }
        return { ok: true, status: 200, text: async () => authoritativeEmptyListHtml };
      }
    });

    const res = await win.fetchExamScheduleAsync('', [], 'https://jwgl.xaut.edu.cn/jsxsd/framework/xsMain.html');
    assert.equal(res.status, 'error');
    assert.equal(res.exams.length, 0);
    assert.ok(res.error && res.error.includes('考试安排网络请求失败'));
  });

  await t.test('场景6: 所有候选学期请求全部成功且均为权威空表（零传输失败） -> status 为 empty', async () => {
    const queryHtml = `
      <!DOCTYPE html><html><body>
        <select name="xnxqid"><option value="2026-2027-1" selected>2026-2027-1</option></select>
      </body></html>
    `;
    const authoritativeEmptyListHtml = `
      <!DOCTYPE html><html><body>
        <table id="dataList">
          <tr><th>序号</th><th>校区</th><th>课程名称</th><th>考试时间</th><th>考场</th></tr>
        </table>
      </body></html>
    `;
    const { win } = setupSandbox({
      fetchHandler: async (url, init) => {
        if (url.includes('/jsxsd/xsks/xsksap_query')) {
          return { ok: true, status: 200, text: async () => queryHtml };
        }
        if (url.includes('/jsxsd/xsks/xsksap_list')) {
          return { ok: true, status: 200, text: async () => authoritativeEmptyListHtml };
        }
        return { ok: false, status: 404, text: async () => '' };
      }
    });

    const res = await win.fetchExamScheduleAsync('2025-2026-2', [], 'https://jwgl.xaut.edu.cn/jsxsd/framework/xsMain.html');
    assert.equal(res.status, 'empty');
    assert.equal(res.exams.length, 0);
    assert.equal(res.error, null);
  });
});
