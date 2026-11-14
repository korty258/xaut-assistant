import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// 强智教务 WebView 注入脚本构建引擎
///
/// 职责单一：负责构建注入强智教务页面的 JavaScript 脚本、Bridge 消息通信
/// 以及跨模块全异步拉取管线（消除 UI 冻结与重复模板定义）。
class SyncScriptBuilder {
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

  /// 顶层运行环境 Origin 白名单安全守卫（防范导航竞态与恶意外跳）
  static const String originGuardJs = '''
    if (typeof window !== 'undefined' && window.location) {
      var proto = window.location.protocol;
      var host = (window.location.hostname || '').toLowerCase();
      if (proto !== 'https:' || !(host === 'xaut.edu.cn' || host.endsWith('.xaut.edu.cn'))) {
        throw new Error('Blocked script execution on untrusted origin: ' + window.location.href);
      }
    }
  ''';

  /// 统一提取的统一身份认证 (CAS) 与登录状态检测函数常量
  ///
  /// 单一定义原则：供所有跨模块异步拉取管线与单页同步注入脚本共享，杜绝多处拷贝维护
  static const String checkAuthJs = '''
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
  ''';

  /// 跨端原生消息桥接与异步 Fetch / 校历探测公共 JS 工具片段
  static String buildAsyncBridgeHelperJs({
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

      $checkAuthJs

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
        var hadTransportError = false;
        var confirmedEmptyExamList = false;

        function isAuthoritativeExamListDoc(doc) {
          if (!doc) return false;
          var exTable = findTableAcrossFrames(doc, function(d) {
            return d.getElementById('dataList') || findTableByKeywords(d, ['课程名称', '考试时间']);
          });
          if (!exTable) return false;
          var trs = exTable.querySelectorAll('tr');
          if (!trs || trs.length === 0) return false;
          for (var r = 0; r < Math.min(trs.length, 3); r++) {
            var thText = (trs[r].textContent || '').replace(/\\s+/g, '');
            if (thText.indexOf('课程名称') !== -1 || thText.indexOf('考试课程') !== -1 || thText.indexOf('考试时间') !== -1) {
              return true;
            }
          }
          if ((exTable.textContent || '').indexOf('未查询到数据') !== -1) {
            return true;
          }
          return false;
        }

        // 0. 若当前处于考试查询页且 DOM 内已直接渲染出考试行，直接提取返回
        if (currentUrl && currentUrl.indexOf('/jsxsd/xsks/') !== -1 && typeof document !== 'undefined') {
          if (checkAuth(document, null, currentUrl)) {
            return { exams: [], status: 'not_logged_in', error: null };
          }
          var liveExams = parseQiangZhiExams(document);
          if (liveExams && liveExams.length > 0) {
            return { exams: liveExams, status: 'ok', error: null };
          }
        }

        // 1. 优先请求考试查询外壳页 /jsxsd/xsks/xsksap_query 提取默认激活学年学期 (xnxqid) 与内嵌 iframe 地址
        var qDoc = null;
        var queryHtml = await fetchHtmlAsync('/jsxsd/xsks/xsksap_query', 12000);
        if (queryHtml === null) {
          hadTransportError = true;
        } else {
          qDoc = new DOMParser().parseFromString(queryHtml, 'text/html');
          if (checkAuth(qDoc, queryHtml, null)) {
            return { exams: [], status: 'not_logged_in', error: null };
          }
          var queryExams = parseQiangZhiExams(qDoc);
          if (queryExams && queryExams.length > 0) {
            return { exams: queryExams, status: 'ok', error: null };
          }
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

        // 3. 携带学年学期参数请求 /jsxsd/xsks/xsksap_list
        for (var cIdx = 0; cIdx < candidateSemesters.length; cIdx++) {
          var sem = candidateSemesters[cIdx];
          var targetUrl = buildExamTargetUrl(iframeUrl, sem);

          var getHtml = await fetchHtmlAsync(targetUrl, 12000);
          if (getHtml === null) {
            hadTransportError = true;
          } else {
            var getDoc = new DOMParser().parseFromString(getHtml, 'text/html');
            if (checkAuth(getDoc, getHtml, null)) {
              return { exams: [], status: 'not_logged_in', error: null };
            }
            var getExams = parseQiangZhiExams(getDoc);
            if (getExams && getExams.length > 0) {
              return { exams: getExams, status: 'ok', error: null };
            }
            if (isAuthoritativeExamListDoc(getDoc)) {
              confirmedEmptyExamList = true;
            }
          }

          var postHtml = await fetchHtmlAsyncPost('/jsxsd/xsks/xsksap_list', 'xnxqid=' + encodeURIComponent(sem), 12000);
          if (postHtml === null) {
            hadTransportError = true;
          } else {
            var postDoc = new DOMParser().parseFromString(postHtml, 'text/html');
            if (checkAuth(postDoc, postHtml, null)) {
              return { exams: [], status: 'not_logged_in', error: null };
            }
            var postExams = parseQiangZhiExams(postDoc);
            if (postExams && postExams.length > 0) {
              return { exams: postExams, status: 'ok', error: null };
            }
            if (isAuthoritativeExamListDoc(postDoc)) {
              confirmedEmptyExamList = true;
            }
          }

          var postFullHtml = await fetchHtmlAsyncPost('/jsxsd/xsks/xsksap_list', 'xqlbmc=&xnxqid=' + encodeURIComponent(sem), 12000);
          if (postFullHtml === null) {
            hadTransportError = true;
          } else {
            var postFullDoc = new DOMParser().parseFromString(postFullHtml, 'text/html');
            if (checkAuth(postFullDoc, postFullHtml, null)) {
              return { exams: [], status: 'not_logged_in', error: null };
            }
            var postFullExams = parseQiangZhiExams(postFullDoc);
            if (postFullExams && postFullExams.length > 0) {
              return { exams: postFullExams, status: 'ok', error: null };
            }
            if (isAuthoritativeExamListDoc(postFullDoc)) {
              confirmedEmptyExamList = true;
            }
          }
        }

        // 4. 终极保底：无参数 GET /jsxsd/xsks/xsksap_list
        if (candidateSemesters.length === 0 || !confirmedEmptyExamList) {
          var fallbackHtml = await fetchHtmlAsync('/jsxsd/xsks/xsksap_list', 12000);
          if (fallbackHtml === null) {
            hadTransportError = true;
          } else {
            var fbDoc = new DOMParser().parseFromString(fallbackHtml, 'text/html');
            if (checkAuth(fbDoc, fallbackHtml, null)) {
              return { exams: [], status: 'not_logged_in', error: null };
            }
            var fbExams = parseQiangZhiExams(fbDoc);
            if (fbExams && fbExams.length > 0) {
              return { exams: fbExams, status: 'ok', error: null };
            }
            if (candidateSemesters.length === 0 && isAuthoritativeExamListDoc(fbDoc)) {
              confirmedEmptyExamList = true;
            }
          }
        }

        if (!hadTransportError && confirmedEmptyExamList) {
          return { exams: [], status: 'empty', error: null };
        }
        return {
          exams: [],
          status: 'error',
          error: hadTransportError
            ? '考试安排网络请求失败或部分响应异常，已保留本地缓存'
            : '未找到考试表格(#dataList)，教务页面可能已改版'
        };
      }
    ''';
  }

  /// 构建轻量级当前教学周被动嗅探脚本
  static Future<String> buildWeekDetectScript({
    String requestId = '',
    int timeoutMs = 12000,
  }) async {
    final jsCode = await loadParserJs();
    final helperJs = buildAsyncBridgeHelperJs(
      requestId: requestId,
      timeoutMs: timeoutMs,
    );
    return '''
      (function() {
        try {
          $originGuardJs
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

  /// 构建课表解析注入代码
  static Future<String> buildCourseInjectionScript({
    String requestId = '',
    int timeoutMs = 30000,
  }) async {
    final jsCode = await loadParserJs();
    final helperJs = buildAsyncBridgeHelperJs(
      requestId: requestId,
      timeoutMs: timeoutMs,
    );
    return '''
      (async function() {
        try {
          $originGuardJs
          $jsCode
          $helperJs
          try {
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
    final helperJs = buildAsyncBridgeHelperJs(
      requestId: requestId,
      timeoutMs: timeoutMs,
    );
    return '''
      (function() {
        try {
          $originGuardJs
          $jsCode
          $helperJs
          try {
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
    final helperJs = buildAsyncBridgeHelperJs(
      requestId: requestId,
      timeoutMs: timeoutMs,
    );
    return '''
      (async function() {
        try {
          $originGuardJs
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

            var exams = parseQiangZhiExams(document);
            if (exams && exams.length > 0) {
              var okRes = { exams: exams, status: 'ok', error: null };
              postToFlutter({ type: 'sync_exams_result', success: true, data: okRes });
              return JSON.stringify(okRes);
            }

            // 若当前处于考试查询外壳页但尚未手动点击网页内查询按钮，自动穿透获取考试列表
            var asyncExamRes = await fetchExamScheduleAsync('', [], currentUrl);
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
    final helperJs = buildAsyncBridgeHelperJs(
      requestId: requestId,
      timeoutMs: timeoutMs,
    );
    return '''
      (async function() {
        try {
          $originGuardJs
          $jsCode
          $helperJs

          try {
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

            // 0. 提取当前教学周与学年学期
            try {
              postToFlutter({ type: 'progress', message: '正在识别教学周与学期...' });
              result.weekInfo = await resolveTeachingWeekWithFallbackAsync(document, currentUrl);
            } catch(e) {}

            // 1. 课表解析
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
              result.errors.courses = e.toString();
            }

            // 2. 成绩解析
            try {
              postToFlutter({ type: 'progress', message: '正在同步历年成绩与GPA...' });
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
                    var gradesArr = result.gradesData.grades || [];
                    result.status.grades = (gradesArr.length > 0) ? 'ok' : 'empty';
                  }
                }
              }
            } catch(e) {
              result.status.grades = 'error';
              result.errors.grades = e.toString();
            }

            // 3. 考试安排解析 (共享全异步拉取管线)
            try {
              postToFlutter({ type: 'progress', message: '正在同步期末考试安排...' });
              var examRes = await fetchExamScheduleAsync(
                result.weekInfo.semester,
                result.gradesData.grades,
                currentUrl
              );
              result.exams = examRes.exams || [];
              result.status.exams = examRes.status;
              result.errors.exams = examRes.error;
            } catch(e) {
              result.status.exams = 'error';
              result.errors.exams = e.toString();
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
}
