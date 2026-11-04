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
});

test('4. 教学周与学期识别回归测试 (parseQiangZhiTeachingWeek)', async (t) => {
  await t.test('首页顶栏样本 (home_week_banner.html) 正确识别周次与学期', () => {
    const doc = loadDomFixture('home_week_banner.html');
    const weekInfo = parser.parseQiangZhiTeachingWeek(doc);

    assert.equal(weekInfo.currentWeek, 9);
    assert.equal(weekInfo.semester, '2026-2027-1');
  });

  await t.test('登录页负例 (login_page.html) 周次为 null 且不抛出异常', () => {
    const doc = loadDomFixture('login_page.html');
    const weekInfo = parser.parseQiangZhiTeachingWeek(doc);

    assert.equal(weekInfo.currentWeek, null);
    assert.equal(weekInfo.semester, '');
  });
});
