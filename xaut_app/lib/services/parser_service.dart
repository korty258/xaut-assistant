import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../models/course.dart';
import '../models/grade.dart';
import '../models/exam.dart';

class ParserService {
  static String? _cachedJsCode;

  @visibleForTesting
  static void setMockJsCode(String? js) {
    _cachedJsCode = js;
  }

  /// 加载内置 assets 中的 qiangzhi_parser.js
  static Future<String> loadParserJs() async {
    if (_cachedJsCode != null) return _cachedJsCode!;
    _cachedJsCode = await rootBundle.loadString('assets/js/qiangzhi_parser.js');
    return _cachedJsCode!;
  }

  /// 跨端原生消息桥接与异步 Fetch / 校历探测公共 JS 工具片段
  static String _buildAsyncBridgeHelperJs({
    required String requestId,
    required int timeoutMs,
  }) {
    final safeRequestId = jsonEncode(requestId);
    return '''
      var reqId = $safeRequestId;
      var timeoutMs = $timeoutMs;
      window.__jinhuaActiveTasks = window.__jinhuaActiveTasks || {};
      var taskState = { aborted: false, controllers: [] };
      if (reqId) {
        window.__jinhuaActiveTasks[reqId] = taskState;
      }

      if (!window.__jinhuaAbortTask) {
        window.__jinhuaAbortTask = function(id) {
          if (!id || !window.__jinhuaActiveTasks) return;
          var task = window.__jinhuaActiveTasks[id];
          if (task) {
            task.aborted = true;
            if (Array.isArray(task.controllers)) {
              for (var i = 0; i < task.controllers.length; i++) {
                try { task.controllers[i].abort(); } catch(e) {}
              }
            }
            delete window.__jinhuaActiveTasks[id];
          }
        };
      }

      if (!window.__jinhuaAbortAllTasks) {
        window.__jinhuaAbortAllTasks = function() {
          if (!window.__jinhuaActiveTasks) return;
          for (var id in window.__jinhuaActiveTasks) {
            if (Object.prototype.hasOwnProperty.call(window.__jinhuaActiveTasks, id)) {
              try { window.__jinhuaAbortTask(id); } catch(e) {}
            }
          }
          window.__jinhuaActiveTasks = {};
        };
      }

      function postToFlutter(msgObj) {
        try {
          if (taskState.aborted && msgObj && msgObj.type !== 'aborted') {
            return false;
          }
          if (typeof msgObj === 'object' && msgObj !== null) {
            if (reqId) {
              msgObj.requestId = reqId;
            }
          }
          var str = typeof msgObj === 'string' ? msgObj : JSON.stringify(msgObj);
          if (typeof window !== 'undefined') {
            if (window.JinhuaBridge && typeof window.JinhuaBridge.postMessage === 'function') {
              window.JinhuaBridge.postMessage(str);
              return true;
            }
            if (window.chrome && window.chrome.webview && typeof window.chrome.webview.postMessage === 'function') {
              window.chrome.webview.postMessage(str);
              return true;
            }
          }
        } catch(e) {}
        return false;
      }

      var deadline = Date.now() + timeoutMs;
      function remainingMs() {
        return Math.max(0, deadline - Date.now());
      }

      async function fetchHtmlAsync(url, optionsOrTimeout) {
        if (taskState.aborted || remainingMs() <= 0) {
          throw new Error('请求超时或已取消');
        }
        var opt = {};
        var maxStepMs = 15000;
        if (typeof optionsOrTimeout === 'number') {
          maxStepMs = optionsOrTimeout;
        } else if (optionsOrTimeout && typeof optionsOrTimeout === 'object') {
          opt = optionsOrTimeout;
          if (typeof opt.timeout === 'number') {
            maxStepMs = opt.timeout;
          }
        }
        var stepBudget = Math.min(maxStepMs || 15000, remainingMs());
        if (stepBudget <= 0) {
          throw new Error('请求超时或已取消');
        }
        try {
          var init = {
            method: opt.method || 'GET',
            credentials: 'include',
            headers: opt.headers || {}
          };
          if (opt.body) {
            init.body = opt.body;
          }
          if (typeof AbortController !== 'undefined') {
            var controller = new AbortController();
            init.signal = controller.signal;
            taskState.controllers.push(controller);
            var timeoutTimer = setTimeout(function() {
              try { controller.abort(); } catch(e) {}
            }, stepBudget);
            try {
              var resp = await fetch(url, init);
              clearTimeout(timeoutTimer);
              var cIdx = taskState.controllers.indexOf(controller);
              if (cIdx !== -1) taskState.controllers.splice(cIdx, 1);
              if (taskState.aborted) throw new Error('请求已取消');
              if (resp && resp.ok) {
                return await resp.text();
              }
            } catch(err) {
              clearTimeout(timeoutTimer);
              var cIdx2 = taskState.controllers.indexOf(controller);
              if (cIdx2 !== -1) taskState.controllers.splice(cIdx2, 1);
              if (taskState.aborted || remainingMs() <= 0) {
                throw new Error('请求超时或已取消');
              }
              return null;
            }
          } else {
            var resp = await fetch(url, init);
            if (taskState.aborted) throw new Error('请求已取消');
            if (resp && resp.ok) {
              return await resp.text();
            }
          }
        } catch(e) {
          if (taskState.aborted || remainingMs() <= 0) {
            throw new Error('请求超时或已取消');
          }
        }
        return null;
      }

      async function fetchHtmlAsyncPost(url, data, maxStepMs) {
        return await fetchHtmlAsync(url, {
          method: 'POST',
          timeout: maxStepMs || 15000,
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8'
          },
          body: data
        });
      }

      async function resolveTeachingWeekWithFallbackAsync(doc, currentUrl) {
        var allowSelect = currentUrl.indexOf('/jsxsd/xskb/') === -1;
        var info = parseQiangZhiTeachingWeek(doc, allowSelect);
        if (info && info.currentWeek) {
          return info;
        }

        var probeUrls = [
          '/jsxsd/framework/xsMain_new.jsp?t1=1',
          '/jsxsd/framework/xsMain.jsp',
          '/jsxsd/framework/xsMain_10700.htmlx'
        ];
        for (var i = 0; i < probeUrls.length; i++) {
          if (taskState.aborted || remainingMs() <= 800) break;
          var html = await fetchHtmlAsync(probeUrls[i], 6000);
          if (html) {
            var pDoc = new DOMParser().parseFromString(html, 'text/html');
            var subInfo = parseQiangZhiTeachingWeek(pDoc, true);
            if (subInfo) {
              if (!info.semester && subInfo.semester) info.semester = subInfo.semester;
              if (subInfo.currentWeek) {
                info.currentWeek = subInfo.currentWeek;
                return info;
              }
            }
          }
        }

        // 终极保底：从强智教学周历 (/jsxsd/jxzl/jxzl_query) 提取第 1 周周一公历日期
        if (!taskState.aborted && remainingMs() > 800) {
          var calHtml = await fetchHtmlAsync('/jsxsd/jxzl/jxzl_query', 6000);
          if (calHtml) {
            var calDoc = new DOMParser().parseFromString(calHtml, 'text/html');
            var startStr = parseQiangZhiCalendarStart(calDoc);
            if (startStr) {
              info.semesterStartDate = startStr;
            }
            if (!info.semester) {
              var calSem = parseQiangZhiTeachingWeek(calDoc, false);
              if (calSem && calSem.semester) info.semester = calSem.semester;
            }
          }
        }

        return info;
      }

      function checkAuth(doc, html, url) {
        if (url && (url.indexOf('/authserver/login') !== -1 || url.indexOf('/authserver/') !== -1)) return true;
        if (doc) {
          if (doc.getElementById('casLoginForm')) return true;
          if (doc.querySelector('form[action*="authserver"]') || doc.querySelector('form[action*="login"]')) {
            if (doc.querySelector('input[name="username"]') && doc.querySelector('input[name="password"]')) {
              return true;
            }
          }
        }
        if (html && typeof html === 'string') {
          if (html.indexOf('casLoginForm') !== -1 || html.indexOf('/authserver/login') !== -1) return true;
        }
        return false;
      }

      function extractExamQueryMeta(qDoc) {
        var meta = { iframeUrl: null, xnxqid: '' };
        if (!qDoc) return meta;

        try {
          var iframes = qDoc.querySelectorAll('iframe, frame');
          for (var f = 0; f < iframes.length; f++) {
            var src = (iframes[f].getAttribute('src') || '').trim();
            if (src && src !== 'about:blank' && (src.indexOf('xsksap_list') !== -1 || src.indexOf('xsks') !== -1)) {
              meta.iframeUrl = src;
              break;
            }
          }
        } catch(e) {}

        try {
          // 必须优先精确查找学年学期下拉框，严禁使用 ', select' 导致误命中前序考试类别下拉框(#xqlbmc)
          var sel =
            qDoc.querySelector('select[name="xnxqid"]') ||
            qDoc.querySelector('#xnxqid') ||
            qDoc.querySelector('select[name="xnxq01id"]') ||
            qDoc.querySelector('#xnxq01id');

          if (!sel) {
            var allSels = qDoc.querySelectorAll('select');
            for (var si = 0; si < allSels.length; si++) {
              var opts = allSels[si].querySelectorAll('option');
              for (var oi = 0; oi < opts.length; oi++) {
                if (/^\\d{4}-\\d{4}-\\d+\$/.test((opts[oi].value || '').trim())) {
                  sel = allSels[si];
                  break;
                }
              }
              if (sel) break;
            }
          }

          if (sel) {
            var opt = sel.querySelector('option[selected]');
            if (opt && (opt.value || '').trim()) {
              meta.xnxqid = opt.value.trim();
            } else if (typeof sel.value === 'string' && /^\\d{4}-\\d{4}-\\d+\$/.test(sel.value.trim())) {
              meta.xnxqid = sel.value.trim();
            } else if (sel.options && sel.options.length > 0) {
              for (var k = 0; k < sel.options.length; k++) {
                var v = (sel.options[k].value || '').trim();
                if (/^\\d{4}-\\d{4}-\\d+\$/.test(v)) {
                  meta.xnxqid = v;
                  break;
                }
              }
              if (!meta.xnxqid) {
                for (var k2 = 0; k2 < sel.options.length; k2++) {
                  var v2 = (sel.options[k2].value || '').trim();
                  if (v2) {
                    meta.xnxqid = v2;
                    break;
                  }
                }
              }
            }
          }
        } catch(e) {}

        return meta;
      }

      function buildExamTargetUrl(iframeUrl, sem) {
        var targetUrl = '/jsxsd/xsks/xsksap_list';
        if (iframeUrl) {
          targetUrl = iframeUrl;
          if (targetUrl.indexOf('/') !== 0 && targetUrl.indexOf('http') !== 0) {
            targetUrl = '/jsxsd/xsks/' + targetUrl;
          }
        }
        if (sem) {
          if (/[?&]xnxqid=/.test(targetUrl)) {
            targetUrl = targetUrl.replace(/([?&]xnxqid=)[^&]*/, '\$1' + encodeURIComponent(sem));
          } else {
            targetUrl += (targetUrl.indexOf('?') !== -1 ? '&' : '?') + 'xnxqid=' + encodeURIComponent(sem);
          }
        }
        return targetUrl;
      }

      async function fetchExamScheduleAsync(fallbackSemester, gradesList, currentUrl) {
        var foundExamTable = false;
        var isNotLoggedIn = false;

        function inspectExamDoc(doc, html) {
          if (checkAuth(doc, html, null)) {
            isNotLoggedIn = true;
            return null;
          }
          if (!doc && html) {
            doc = new DOMParser().parseFromString(html, 'text/html');
          }
          if (!doc) return null;
          if (checkAuth(doc, null, null)) {
            isNotLoggedIn = true;
            return null;
          }
          var exTable = findTableAcrossFrames(doc, function(d) {
            return d.getElementById('dataList') || findTableByKeywords(d, ['课程名称', '考试时间']);
          });
          if (exTable) {
            foundExamTable = true;
            var parsed = parseQiangZhiExams(doc);
            if (parsed && parsed.length > 0) {
              return parsed;
            }
          }
          return null;
        }

        // 0. 若当前已处于考试查询页且 DOM 内已渲染出考试行，直接提取返回
        if (currentUrl && currentUrl.indexOf('/jsxsd/xsks/') !== -1 && typeof document !== 'undefined') {
          var liveExams = inspectExamDoc(document, null);
          if (isNotLoggedIn) {
            return { exams: [], status: 'not_logged_in', error: null };
          }
          if (liveExams && liveExams.length > 0) {
            return { exams: liveExams, status: 'ok', error: null };
          }
        }

        // 1. 优先请求考试查询外壳页 /jsxsd/xsks/xsksap_query 提取默认激活学年学期 (xnxqid) 与内嵌 iframe 地址
        //    （严禁先无参请求 /jsxsd/xsks/xsksap_list 并以 hasExamTable 短路，因无参请求仍会返回空 #dataList 表壳导致跳过参数查询）
        var qDoc = null;
        var queryHtml = await fetchHtmlAsync('/jsxsd/xsks/xsksap_query', 12000);
        if (queryHtml) {
          var queryExams = inspectExamDoc(null, queryHtml);
          if (isNotLoggedIn) {
            return { exams: [], status: 'not_logged_in', error: null };
          }
          if (queryExams && queryExams.length > 0) {
            return { exams: queryExams, status: 'ok', error: null };
          }
          qDoc = new DOMParser().parseFromString(queryHtml, 'text/html');
        }

        var queryMeta = extractExamQueryMeta(qDoc);
        var liveMeta = (currentUrl && currentUrl.indexOf('/jsxsd/xsks/') !== -1 && typeof document !== 'undefined')
          ? extractExamQueryMeta(document)
          : { iframeUrl: null, xnxqid: '' };
        var iframeUrl = queryMeta.iframeUrl || liveMeta.iframeUrl;

        // 2. 汇总候选学年学期列表 (按 考试外壳页选中学期 -> 当前页选中学期 -> 教务顶栏/课表学期 -> 最新成绩学期 优先级去重)
        var candidateSemesters = [];
        function addCandidateSem(s) {
          var trimmed = (s || '').trim();
          if (trimmed && candidateSemesters.indexOf(trimmed) === -1) {
            candidateSemesters.push(trimmed);
          }
        }
        addCandidateSem(liveMeta.xnxqid);
        addCandidateSem(queryMeta.xnxqid);
        addCandidateSem(fallbackSemester);
        if (Array.isArray(gradesList) && gradesList.length > 0) {
          var sems = gradesList
            .map(function(g) { return (g && g.semester ? String(g.semester) : '').trim(); })
            .filter(function(s) { return s.length > 0; })
            .sort();
          if (sems.length > 0) {
            addCandidateSem(sems[sems.length - 1]);
          }
        }

        // 3. 携带学年学期参数请求 /jsxsd/xsks/xsksap_list（若 GET 返回空表壳 0 条记录，继续尝试 POST 表单提交）
        for (var cIdx = 0; cIdx < candidateSemesters.length; cIdx++) {
          var sem = candidateSemesters[cIdx];
          var targetUrl = buildExamTargetUrl(iframeUrl, sem);

          var getHtml = await fetchHtmlAsync(targetUrl, 12000);
          if (getHtml) {
            var getExams = inspectExamDoc(null, getHtml);
            if (isNotLoggedIn) {
              return { exams: [], status: 'not_logged_in', error: null };
            }
            if (getExams && getExams.length > 0) {
              return { exams: getExams, status: 'ok', error: null };
            }
          }

          var postHtml = await fetchHtmlAsyncPost('/jsxsd/xsks/xsksap_list', 'xnxqid=' + encodeURIComponent(sem), 12000);
          if (postHtml) {
            var postExams = inspectExamDoc(null, postHtml);
            if (isNotLoggedIn) {
              return { exams: [], status: 'not_logged_in', error: null };
            }
            if (postExams && postExams.length > 0) {
              return { exams: postExams, status: 'ok', error: null };
            }
          }

          var postFullHtml = await fetchHtmlAsyncPost('/jsxsd/xsks/xsksap_list', 'xqlbmc=&xnxqid=' + encodeURIComponent(sem), 12000);
          if (postFullHtml) {
            var postFullExams = inspectExamDoc(null, postFullHtml);
            if (isNotLoggedIn) {
              return { exams: [], status: 'not_logged_in', error: null };
            }
            if (postFullExams && postFullExams.length > 0) {
              return { exams: postFullExams, status: 'ok', error: null };
            }
          }
        }

        // 4. 终极保底：无参数 GET /jsxsd/xsks/xsksap_list
        var fallbackHtml = await fetchHtmlAsync('/jsxsd/xsks/xsksap_list', 12000);
        if (fallbackHtml) {
          var fbExams = inspectExamDoc(null, fallbackHtml);
          if (isNotLoggedIn) {
            return { exams: [], status: 'not_logged_in', error: null };
          }
          if (fbExams && fbExams.length > 0) {
            return { exams: fbExams, status: 'ok', error: null };
          }
        }

        if (isNotLoggedIn) {
          return { exams: [], status: 'not_logged_in', error: null };
        }
        if (foundExamTable) {
          return { exams: [], status: 'empty', error: null };
        }
        return {
          exams: [],
          status: 'error',
          error: '未找到考试表格(#dataList)，教务页面可能已改版'
        };
      }
    ''';
  }

  /// 顶层运行环境 Origin 白名单安全守卫（防范导航竞态与恶意外跳）
  static const String _originGuardJs = '''
    if (typeof window !== 'undefined' && window.location) {
      var proto = window.location.protocol;
      var host = (window.location.hostname || '').toLowerCase();
      if (proto !== 'https:' || !(host === 'xaut.edu.cn' || host.endsWith('.xaut.edu.cn'))) {
        throw new Error('Blocked script execution on untrusted origin: ' + window.location.href);
      }
    }
  ''';

  /// 构建轻量级当前教学周被动嗅探脚本（供教务主页加载完成时静默捕获右上角「2026-2027-1 第9周」）
  static Future<String> buildWeekDetectScript({
    String requestId = '',
    int timeoutMs = 12000,
  }) async {
    final jsCode = await loadParserJs();
    final helperJs = _buildAsyncBridgeHelperJs(
      requestId: requestId,
      timeoutMs: timeoutMs,
    );
    return '''
      (function() {
        try {
          $_originGuardJs
          $jsCode
          $helperJs
          try {
            var allowSelect = window.location.href.indexOf('/jsxsd/xskb/') === -1;
            var info = parseQiangZhiTeachingWeek(document, allowSelect);
            postToFlutter({ type: 'detect_week_result', success: true, data: info });
            return JSON.stringify(info);
          } finally {
            if (reqId && window.__jinhuaActiveTasks) {
              delete window.__jinhuaActiveTasks[reqId];
            }
          }
        } catch(e) {
          postToFlutter({ type: 'detect_week_result', success: false, error: e.toString() });
          return JSON.stringify({ error: e.toString() });
        }
      })();
    ''';
  }

  /// 构建课表解析注入代码（顺带提取当前教学周次与学期）
  static Future<String> buildCourseInjectionScript({
    String requestId = '',
    int timeoutMs = 30000,
  }) async {
    final jsCode = await loadParserJs();
    final helperJs = _buildAsyncBridgeHelperJs(
      requestId: requestId,
      timeoutMs: timeoutMs,
    );
    return '''
      (async function() {
        try {
          $_originGuardJs
          $jsCode
          $helperJs
          try {
            function checkAuth(doc, html, url) {
              if (url && (url.indexOf('/authserver/login') !== -1 || url.indexOf('/authserver/') !== -1)) return true;
              if (doc) {
                if (doc.getElementById('casLoginForm')) return true;
                if (doc.querySelector('form[action*="authserver"]') || doc.querySelector('form[action*="login"]')) {
                  if (doc.querySelector('input[name="username"]') && doc.querySelector('input[name="password"]')) {
                    return true;
                  }
                }
              }
              if (html && typeof html === 'string') {
                if (html.indexOf('casLoginForm') !== -1 || html.indexOf('/authserver/login') !== -1) return true;
              }
              return false;
            }

            var isAuth = checkAuth(document, null, window.location.href);
            var kbTable = findTableAcrossFrames(document, function(d) {
              return d.getElementById('timetable') || d.getElementById('kbtable');
            });
            var courses = parseQiangZhiCourses(document);
            var weekInfo = await resolveTeachingWeekWithFallbackAsync(document, window.location.href);
            var status = isAuth ? 'not_logged_in' : (!kbTable ? 'error' : (courses.length > 0 ? 'ok' : 'empty'));
            var res = {
              courses: courses,
              weekInfo: weekInfo,
              status: status,
              error: (!kbTable && !isAuth) ? '未找到课表表格' : null
            };
            postToFlutter({ type: 'sync_course_result', success: true, data: res });
            return JSON.stringify(res);
          } finally {
            if (reqId && window.__jinhuaActiveTasks) {
              delete window.__jinhuaActiveTasks[reqId];
            }
          }
        } catch(e) {
          postToFlutter({ type: 'sync_course_result', success: false, error: e.toString() });
          return JSON.stringify({ error: e.toString() });
        }
      })();
    ''';
  }

  /// 构建成绩解析注入代码
  static Future<String> buildGradesInjectionScript({
    String requestId = '',
    int timeoutMs = 30000,
  }) async {
    final jsCode = await loadParserJs();
    final helperJs = _buildAsyncBridgeHelperJs(
      requestId: requestId,
      timeoutMs: timeoutMs,
    );
    return '''
      (function() {
        try {
          $_originGuardJs
          $jsCode
          $helperJs
          try {
            function checkAuth(doc, html, url) {
              if (url && (url.indexOf('/authserver/login') !== -1 || url.indexOf('/authserver/') !== -1)) return true;
              if (doc) {
                if (doc.getElementById('casLoginForm')) return true;
                if (doc.querySelector('form[action*="authserver"]') || doc.querySelector('form[action*="login"]')) {
                  if (doc.querySelector('input[name="username"]') && doc.querySelector('input[name="password"]')) {
                    return true;
                  }
                }
              }
              return false;
            }
            var isAuth = checkAuth(document, null, window.location.href);
            var cjTable = findTableAcrossFrames(document, function(d) {
              return d.getElementById('dataList') || findTableByKeywords(d, ['课程名称', '成绩']);
            });
            var res = parseQiangZhiGrades(document);
            var status = isAuth ? 'not_logged_in' : (!cjTable ? 'error' : ((res.grades && res.grades.length > 0) ? 'ok' : 'empty'));
            res.status = status;
            res.error = (!cjTable && !isAuth) ? '未找到成绩表格' : null;
            postToFlutter({ type: 'sync_grades_result', success: true, data: res });
            return JSON.stringify(res);
          } finally {
            if (reqId && window.__jinhuaActiveTasks) {
              delete window.__jinhuaActiveTasks[reqId];
            }
          }
        } catch(e) {
          postToFlutter({ type: 'sync_grades_result', success: false, error: e.toString() });
          return JSON.stringify({ error: e.toString() });
        }
      })();
    ''';
  }

  /// 构建考试安排解析注入代码
  static Future<String> buildExamsInjectionScript({
    String requestId = '',
    int timeoutMs = 30000,
  }) async {
    final jsCode = await loadParserJs();
    final helperJs = _buildAsyncBridgeHelperJs(
      requestId: requestId,
      timeoutMs: timeoutMs,
    );
    return '''
      (async function() {
        try {
          $_originGuardJs
          $jsCode
          $helperJs
          try {
            var currentUrl = window.location.href;
            var isAuth = checkAuth(document, null, currentUrl);
            if (isAuth) {
              var authRes = { exams: [], status: 'not_logged_in', error: null };
              postToFlutter({ type: 'sync_exams_result', success: true, data: authRes });
              return JSON.stringify(authRes);
            }

            var exTable = findTableAcrossFrames(document, function(d) {
              return d.getElementById('dataList') || findTableByKeywords(d, ['课程名称', '考试时间']);
            });
            var exams = parseQiangZhiExams(document);

            if (exams && exams.length > 0) {
              var okRes = { exams: exams, status: 'ok', error: null };
              postToFlutter({ type: 'sync_exams_result', success: true, data: okRes });
              return JSON.stringify(okRes);
            }

            // 若当前处于考试查询外壳页但尚未手动点击网页内查询按钮，自动穿透获取考试列表
            var asyncExamRes = await fetchExamScheduleAsync('', [], currentUrl);
            if (asyncExamRes.status === 'error' && exTable) {
              asyncExamRes = { exams: [], status: 'empty', error: null };
            }
            postToFlutter({ type: 'sync_exams_result', success: true, data: asyncExamRes });
            return JSON.stringify(asyncExamRes);
          } finally {
            if (reqId && window.__jinhuaActiveTasks) {
              delete window.__jinhuaActiveTasks[reqId];
            }
          }
        } catch(e) {
          postToFlutter({ type: 'sync_exams_result', success: false, error: e.toString() });
          return JSON.stringify({ error: e.toString() });
        }
      })();
    ''';
  }

  /// 构建全量一键同步脚本 (课表 + 成绩 + 考试 + 当前教学周 跨模块一次性同步)
  static Future<String> buildSyncAllInjectionScript({
    String requestId = '',
    int timeoutMs = 30000,
  }) async {
    final jsCode = await loadParserJs();
    final helperJs = _buildAsyncBridgeHelperJs(
      requestId: requestId,
      timeoutMs: timeoutMs,
    );
    return '''
      (async function() {
        try {
          $_originGuardJs
          $jsCode
          $helperJs

          try {
            function checkAuth(doc, html, url) {
              if (url && (url.indexOf('/authserver/login') !== -1 || url.indexOf('/authserver/') !== -1)) return true;
              if (doc) {
                if (doc.getElementById('casLoginForm')) return true;
                if (doc.querySelector('form[action*="authserver"]') || doc.querySelector('form[action*="login"]')) {
                  if (doc.querySelector('input[name="username"]') && doc.querySelector('input[name="password"]')) {
                    return true;
                  }
                }
              }
              if (html && typeof html === 'string') {
                if (html.indexOf('casLoginForm') !== -1 || html.indexOf('/authserver/login') !== -1) return true;
              }
              return false;
            }

            var result = {
              courses: [],
              gradesData: { grades: [], summary: {} },
              exams: [],
              weekInfo: { currentWeek: null, semester: '', semesterStartDate: '' },
              status: {
                courses: 'empty',
                grades: 'empty',
                exams: 'empty'
              },
              errors: {
                courses: null,
                grades: null,
                exams: null
              }
            };

            var currentUrl = window.location.href;

            // 0. 提取当前教学周与学年学期（教务主页右上角天然带有 "2026-2027-1 第9周"）
            try {
              postToFlutter({ type: 'progress', message: '正在识别教学周与学期...' });
              result.weekInfo = await resolveTeachingWeekWithFallbackAsync(document, currentUrl);
            } catch(e) {}

            // 1. 课表解析（始终请求默认全量课表，严禁直接读 document 以免页面筛选导致误清空）
            try {
              postToFlutter({ type: 'progress', message: '正在同步课表数据...' });
              var kbDoc = null;
              var kbHtml = await fetchHtmlAsync('/jsxsd/xskb/xskb_list.do', 15000);
              if (checkAuth(null, kbHtml, null)) {
                result.status.courses = 'not_logged_in';
              } else if (kbHtml) {
                kbDoc = new DOMParser().parseFromString(kbHtml, 'text/html');
              } else {
                result.status.courses = 'error';
                result.errors.courses = '课表请求响应为空或网络异常';
              }

              if (result.status.courses !== 'not_logged_in' && kbDoc) {
                if (checkAuth(kbDoc, null, null)) {
                  result.status.courses = 'not_logged_in';
                } else {
                  var kbTable = findTableAcrossFrames(kbDoc, function(d) {
                    return d.getElementById('timetable') || d.getElementById('kbtable');
                  });
                  if (!kbTable) {
                    result.status.courses = 'error';
                    result.errors.courses = '未找到课表表格(#timetable/#kbtable)，教务页面可能已改版';
                  } else {
                    result.courses = parseQiangZhiCourses(kbDoc);
                    result.status.courses = (result.courses && result.courses.length > 0) ? 'ok' : 'empty';
                    if (!result.weekInfo.semester) {
                      var kbSem = parseQiangZhiTeachingWeek(kbDoc, false);
                      if (kbSem && kbSem.semester) {
                        result.weekInfo.semester = kbSem.semester;
                      }
                    }
                  }
                }
              }
            } catch(e) {
              result.status.courses = 'error';
              result.errors.courses = String(e);
            }

            // 2. 成绩解析（始终请求全量成绩列表，严禁直接读 document 以免页面筛选导致误清空）
            try {
              postToFlutter({ type: 'progress', message: '正在同步学业成绩...' });
              var cjDoc = null;
              var cjHtml = await fetchHtmlAsync('/jsxsd/kscj/cjcx_list', 15000);
              if (checkAuth(null, cjHtml, null)) {
                result.status.grades = 'not_logged_in';
              } else if (cjHtml) {
                cjDoc = new DOMParser().parseFromString(cjHtml, 'text/html');
              } else {
                result.status.grades = 'error';
                result.errors.grades = '成绩请求响应为空或网络异常';
              }

              if (result.status.grades !== 'not_logged_in' && cjDoc) {
                if (checkAuth(cjDoc, null, null)) {
                  result.status.grades = 'not_logged_in';
                } else {
                  var cjTable = findTableAcrossFrames(cjDoc, function(d) {
                    return d.getElementById('dataList') || findTableByKeywords(d, ['课程名称', '成绩']);
                  });
                  if (!cjTable) {
                    result.status.grades = 'error';
                    result.errors.grades = '未找到成绩表格(#dataList)，教务页面可能已改版';
                  } else {
                    result.gradesData = parseQiangZhiGrades(cjDoc);
                    result.status.grades = (result.gradesData && result.gradesData.grades && result.gradesData.grades.length > 0) ? 'ok' : 'empty';
                  }
                }
              }
            } catch(e) {
              result.status.grades = 'error';
              result.errors.grades = String(e);
            }

            // 3. 考试安排解析（深度穿透外壳页与参数自动提取）
            try {
              postToFlutter({ type: 'progress', message: '正在查询考试安排...' });
              var examGrades = (result.gradesData && result.gradesData.grades) ? result.gradesData.grades : [];
              var examSem = (result.weekInfo && result.weekInfo.semester) ? result.weekInfo.semester : '';
              var examRes = await fetchExamScheduleAsync(examSem, examGrades, currentUrl);
              result.exams = examRes.exams || [];
              result.status.exams = examRes.status || 'error';
              result.errors.exams = examRes.error || null;
            } catch(e) {
              result.status.exams = 'error';
              result.errors.exams = String(e);
            }

            postToFlutter({ type: 'sync_all_result', success: true, data: result });
            return JSON.stringify(result);
          } finally {
            if (reqId && window.__jinhuaActiveTasks) {
              delete window.__jinhuaActiveTasks[reqId];
            }
          }
        } catch(e) {
          postToFlutter({ type: 'sync_all_result', success: false, error: e.toString() });
          return JSON.stringify({ error: e.toString() });
        }
      })();
    ''';
  }

  static dynamic _unwrapJson(dynamic rawResult) {
    if (rawResult == null) return null;
    dynamic data = rawResult;
    if (data is String) {
      data = jsonDecode(data);
      if (data is String) {
        data = jsonDecode(data);
      }
    }
    return data;
  }

  /// 解析当前教学周识别结果
  static ({int? currentWeek, String? semester, DateTime? semesterStartDate}) parseWeekInfoResult(dynamic rawResult) {
    if (rawResult == null) {
      return (currentWeek: null, semester: null, semesterStartDate: null);
    }

    dynamic data = rawResult;
    try {
      data = _unwrapJson(rawResult);
    } catch (_) {
      return (currentWeek: null, semester: null, semesterStartDate: null);
    }

    if (data is Map) {
      int? week;
      final rawWeek = data['currentWeek'];
      if (rawWeek is int) {
        week = rawWeek;
      } else if (rawWeek is num) {
        week = rawWeek.toInt();
      } else if (rawWeek is String) {
        week = int.tryParse(rawWeek.trim());
      }
      if (week != null && (week < 1 || week > 30)) {
        week = null;
      }

      String? semester;
      final rawSem = data['semester'];
      if (rawSem is String && rawSem.trim().isNotEmpty) {
        semester = rawSem.trim();
      }

      DateTime? startDate;
      final rawStart = data['semesterStartDate'];
      if (rawStart is String && rawStart.trim().isNotEmpty) {
        final parsed = DateTime.tryParse(rawStart.trim());
        if (parsed != null) {
          startDate = DateTime(parsed.year, parsed.month, parsed.day);
        }
      }

      return (currentWeek: week, semester: semester, semesterStartDate: startDate);
    }

    return (currentWeek: null, semester: null, semesterStartDate: null);
  }

  /// 统一处理 WebView 返回的全量同步结果
  static SyncAllResult parseSyncAllResult(dynamic rawResult) {
    if (rawResult == null) {
      return const SyncAllResult(
        courses: [],
        grades: [],
        exams: [],
        statusCourses: SyncModuleStatus.error,
        statusGrades: SyncModuleStatus.error,
        statusExams: SyncModuleStatus.error,
        error: '执行结果为空',
      );
    }

    dynamic data;
    try {
      data = _unwrapJson(rawResult);
    } catch (e) {
      return SyncAllResult(
        courses: const [],
        grades: const [],
        exams: const [],
        statusCourses: SyncModuleStatus.error,
        statusGrades: SyncModuleStatus.error,
        statusExams: SyncModuleStatus.error,
        error: 'JSON反序列化失败: $e',
      );
    }

    if (data is Map) {
      if (data['success'] == false || (data['error'] != null && data['status'] == null)) {
        final errText = data['error']?.toString() ?? '同步脚本执行异常';
        return SyncAllResult(
          courses: const [],
          grades: const [],
          exams: const [],
          statusCourses: SyncModuleStatus.error,
          statusGrades: SyncModuleStatus.error,
          statusExams: SyncModuleStatus.error,
          errorCourses: errText,
          errorGrades: errText,
          errorExams: errText,
          error: errText,
        );
      }

      final courses = parseCoursesResult(data['courses']);
      final gradesResult = parseGradesResult(data['gradesData']);
      final exams = parseExamsResult(data['exams']);
      final weekInfo = parseWeekInfoResult(data['weekInfo']);

      final statusMap = data['status'] is Map ? data['status'] as Map : const {};
      final errorsMap = data['errors'] is Map ? data['errors'] as Map : const {};

      final statusCourses = SyncModuleStatus.fromString(
        statusMap['courses']?.toString(),
        fallbackOk: courses.isNotEmpty,
        defaultStatus: SyncModuleStatus.error,
      );
      final statusGrades = SyncModuleStatus.fromString(
        statusMap['grades']?.toString(),
        fallbackOk: gradesResult.grades.isNotEmpty,
        defaultStatus: SyncModuleStatus.error,
      );
      final statusExams = SyncModuleStatus.fromString(
        statusMap['exams']?.toString(),
        fallbackOk: exams.isNotEmpty,
        defaultStatus: SyncModuleStatus.error,
      );

      return SyncAllResult(
        courses: courses,
        grades: gradesResult.grades,
        gradeSummary: gradesResult.summary,
        exams: exams,
        statusCourses: statusCourses,
        statusGrades: statusGrades,
        statusExams: statusExams,
        errorCourses: errorsMap['courses']?.toString(),
        errorGrades: errorsMap['grades']?.toString(),
        errorExams: errorsMap['exams']?.toString(),
        detectedWeek: weekInfo.currentWeek,
        detectedSemester: weekInfo.semester,
        detectedSemesterStart: weekInfo.semesterStartDate,
        error: data['error'] as String?,
      );
    }

    return const SyncAllResult(
      courses: [],
      grades: [],
      exams: [],
      statusCourses: SyncModuleStatus.error,
      statusGrades: SyncModuleStatus.error,
      statusExams: SyncModuleStatus.error,
      error: '数据格式异常',
    );
  }

  /// 统一处理单页课表同步结果（同时包含课程列表与自动识别的周次）
  static ({
    List<Course> courses,
    int? detectedWeek,
    String? detectedSemester,
    DateTime? detectedSemesterStart,
    SyncModuleStatus status,
    String? error,
  }) parseCourseSyncResult(dynamic rawResult) {
    if (rawResult == null) {
      return (
        courses: <Course>[],
        detectedWeek: null,
        detectedSemester: null,
        detectedSemesterStart: null,
        status: SyncModuleStatus.error,
        error: '执行结果为空',
      );
    }

    dynamic data;
    try {
      data = _unwrapJson(rawResult);
    } catch (_) {
      return (
        courses: <Course>[],
        detectedWeek: null,
        detectedSemester: null,
        detectedSemesterStart: null,
        status: SyncModuleStatus.error,
        error: 'JSON反序列化失败',
      );
    }

    if (data is Map) {
      if (data['success'] == false || (data['error'] != null && data['status'] == null)) {
        final error = data['error']?.toString() ?? '同步脚本执行异常';
        return (
          courses: <Course>[],
          detectedWeek: null,
          detectedSemester: null,
          detectedSemesterStart: null,
          status: SyncModuleStatus.error,
          error: error,
        );
      }

      final courses = parseCoursesResult(data['courses']);
      final weekInfo = parseWeekInfoResult(data['weekInfo']);
      final statusStr = data['status']?.toString();
      final bool hasCoursesKey = data.containsKey('courses') && data['courses'] is List;
      final status = SyncModuleStatus.fromString(
        statusStr,
        fallbackOk: courses.isNotEmpty,
        defaultStatus: (hasCoursesKey && data['error'] == null)
            ? SyncModuleStatus.empty
            : SyncModuleStatus.error,
      );
      final error = data['error']?.toString();
      return (
        courses: courses,
        detectedWeek: weekInfo.currentWeek,
        detectedSemester: weekInfo.semester,
        detectedSemesterStart: weekInfo.semesterStartDate,
        status: status,
        error: error,
      );
    }

    if (data is List) {
      final courses = parseCoursesResult(data);
      return (
        courses: courses,
        detectedWeek: null,
        detectedSemester: null,
        detectedSemesterStart: null,
        status: courses.isNotEmpty ? SyncModuleStatus.ok : SyncModuleStatus.empty,
        error: null,
      );
    }

    return (
      courses: <Course>[],
      detectedWeek: null,
      detectedSemester: null,
      detectedSemesterStart: null,
      status: SyncModuleStatus.error,
      error: '数据格式异常',
    );
  }

  /// 统一处理 WebView 返回的执行结果为 Course 列表（兼容数组或带 courses 字段的对象）
  static List<Course> parseCoursesResult(dynamic rawResult) {
    if (rawResult == null) return [];

    dynamic data;
    try {
      data = _unwrapJson(rawResult);
    } catch (_) {
      return [];
    }

    if (data is Map && data['courses'] is List) {
      data = data['courses'];
    }

    if (data is List) {
      return data.map((item) {
        if (item is Map<String, dynamic>) {
          return Course.fromJson(item);
        } else if (item is Map) {
          return Course.fromJson(Map<String, dynamic>.from(item));
        }
        return null;
      }).whereType<Course>().toList();
    }

    return [];
  }

  /// 统一处理 WebView 返回的成绩执行结果
  static ({
    List<GradeItem> grades,
    GradeSummary? summary,
    SyncModuleStatus status,
    String? error,
  }) parseGradesResult(dynamic rawResult) {
    if (rawResult == null) {
      return (
        grades: <GradeItem>[],
        summary: null,
        status: SyncModuleStatus.error,
        error: '执行结果为空',
      );
    }

    dynamic data;
    try {
      data = _unwrapJson(rawResult);
    } catch (_) {
      return (
        grades: <GradeItem>[],
        summary: null,
        status: SyncModuleStatus.error,
        error: 'JSON反序列化失败',
      );
    }

    if (data is Map) {
      if (data['success'] == false || (data['error'] != null && data['status'] == null)) {
        final error = data['error']?.toString() ?? '同步脚本执行异常';
        return (
          grades: <GradeItem>[],
          summary: null,
          status: SyncModuleStatus.error,
          error: error,
        );
      }

      List<GradeItem> grades = [];
      GradeSummary? summary;

      if (data['grades'] is List) {
        grades = (data['grades'] as List).map((item) {
          if (item is Map<String, dynamic>) {
            return GradeItem.fromJson(item);
          } else if (item is Map) {
            return GradeItem.fromJson(Map<String, dynamic>.from(item));
          }
          return null;
        }).whereType<GradeItem>().toList();
      }

      if (data['summary'] is Map) {
        final sumMap = data['summary'];
        summary = GradeSummary.fromJson(
          sumMap is Map<String, dynamic> ? sumMap : Map<String, dynamic>.from(sumMap),
        );
      }

      final statusStr = data['status']?.toString();
      final bool hasGradesKey = data.containsKey('grades') && data['grades'] is List;
      final status = SyncModuleStatus.fromString(
        statusStr,
        fallbackOk: grades.isNotEmpty,
        defaultStatus: (hasGradesKey && data['error'] == null)
            ? SyncModuleStatus.empty
            : SyncModuleStatus.error,
      );
      final error = data['error']?.toString();
      return (grades: grades, summary: summary, status: status, error: error);
    }

    if (data is List) {
      final grades = data.map((item) {
        if (item is Map<String, dynamic>) {
          return GradeItem.fromJson(item);
        } else if (item is Map) {
          return GradeItem.fromJson(Map<String, dynamic>.from(item));
        }
        return null;
      }).whereType<GradeItem>().toList();
      return (
        grades: grades,
        summary: null,
        status: grades.isNotEmpty ? SyncModuleStatus.ok : SyncModuleStatus.empty,
        error: null,
      );
    }

    return (
      grades: <GradeItem>[],
      summary: null,
      status: SyncModuleStatus.error,
      error: '数据格式异常',
    );
  }

  /// 统一处理 WebView 返回的考试安排执行结果（带状态与错误诊断）
  static ({
    List<ExamItem> exams,
    SyncModuleStatus status,
    String? error,
  }) parseExamsDetailedResult(dynamic rawResult) {
    if (rawResult == null) {
      return (
        exams: <ExamItem>[],
        status: SyncModuleStatus.error,
        error: '执行结果为空',
      );
    }

    dynamic data;
    try {
      data = _unwrapJson(rawResult);
    } catch (_) {
      return (
        exams: <ExamItem>[],
        status: SyncModuleStatus.error,
        error: 'JSON反序列化失败',
      );
    }

    if (data is Map) {
      if (data['success'] == false || (data['error'] != null && data['status'] == null)) {
        final error = data['error']?.toString() ?? '同步脚本执行异常';
        return (
          exams: <ExamItem>[],
          status: SyncModuleStatus.error,
          error: error,
        );
      }

      final exams = parseExamsResult(data['exams'] ?? data);
      final statusStr = data['status']?.toString();
      final bool hasExamsKey = data.containsKey('exams') && data['exams'] is List;
      final status = SyncModuleStatus.fromString(
        statusStr,
        fallbackOk: exams.isNotEmpty,
        defaultStatus: (hasExamsKey && data['error'] == null)
            ? SyncModuleStatus.empty
            : SyncModuleStatus.error,
      );
      final error = data['error']?.toString();

      return (exams: exams, status: status, error: error);
    }

    if (data is List) {
      final exams = parseExamsResult(data);
      return (
        exams: exams,
        status: exams.isNotEmpty ? SyncModuleStatus.ok : SyncModuleStatus.empty,
        error: null,
      );
    }

    return (
      exams: <ExamItem>[],
      status: SyncModuleStatus.error,
      error: '数据格式异常',
    );
  }

  /// 统一处理 WebView 返回的考试安排执行结果
  static List<ExamItem> parseExamsResult(dynamic rawResult) {
    if (rawResult == null) return [];

    dynamic data;
    try {
      data = _unwrapJson(rawResult);
    } catch (_) {
      return [];
    }

    if (data is List) {
      return data.map((item) {
        if (item is Map<String, dynamic>) {
          return ExamItem.fromJson(item);
        } else if (item is Map) {
          return ExamItem.fromJson(Map<String, dynamic>.from(item));
        }
        return null;
      }).whereType<ExamItem>().toList();
    }

    return [];
  }
}

/// 模块同步状态枚举 (细化三态/四态：成功、无数据、未登录、异常改版)
enum SyncModuleStatus {
  ok,
  empty,
  notLoggedIn,
  error;

  static SyncModuleStatus fromString(
    String? val, {
    bool fallbackOk = false,
    SyncModuleStatus defaultStatus = SyncModuleStatus.error,
  }) {
    switch (val?.toLowerCase()) {
      case 'ok':
        return SyncModuleStatus.ok;
      case 'empty':
        return SyncModuleStatus.empty;
      case 'not_logged_in':
        return SyncModuleStatus.notLoggedIn;
      case 'error':
        return SyncModuleStatus.error;
      default:
        return fallbackOk ? SyncModuleStatus.ok : defaultStatus;
    }
  }

  bool get isOk => this == SyncModuleStatus.ok;
  bool get isEmpty => this == SyncModuleStatus.empty;
  bool get isNotLoggedIn => this == SyncModuleStatus.notLoggedIn;
  bool get isError => this == SyncModuleStatus.error;
}

class SyncAllResult {
  final List<Course> courses;
  final List<GradeItem> grades;
  final GradeSummary? gradeSummary;
  final List<ExamItem> exams;
  final SyncModuleStatus statusCourses;
  final SyncModuleStatus statusGrades;
  final SyncModuleStatus statusExams;
  final String? errorCourses;
  final String? errorGrades;
  final String? errorExams;
  final int? detectedWeek;
  final String? detectedSemester;
  final DateTime? detectedSemesterStart;
  final String? error;

  const SyncAllResult({
    required this.courses,
    required this.grades,
    this.gradeSummary,
    required this.exams,
    this.statusCourses = SyncModuleStatus.empty,
    this.statusGrades = SyncModuleStatus.empty,
    this.statusExams = SyncModuleStatus.empty,
    this.errorCourses,
    this.errorGrades,
    this.errorExams,
    this.detectedWeek,
    this.detectedSemester,
    this.detectedSemesterStart,
    this.error,
  });

  bool get hasCourses => courses.isNotEmpty;
  bool get hasGrades => grades.isNotEmpty;
  bool get hasExams => exams.isNotEmpty;
  bool get hasAnyData => hasCourses || hasGrades || hasExams;

  bool get isAnyNotLoggedIn =>
      statusCourses == SyncModuleStatus.notLoggedIn ||
      statusGrades == SyncModuleStatus.notLoggedIn ||
      statusExams == SyncModuleStatus.notLoggedIn;

  bool get isAnyError =>
      statusCourses == SyncModuleStatus.error ||
      statusGrades == SyncModuleStatus.error ||
      statusExams == SyncModuleStatus.error;
}
