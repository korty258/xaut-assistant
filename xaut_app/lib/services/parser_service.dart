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
            var exTable = findTableAcrossFrames(document, function(d) {
              return d.getElementById('dataList') || findTableByKeywords(d, ['课程名称', '考试时间']);
            });
            var exams = parseQiangZhiExams(document);
            var status = isAuth ? 'not_logged_in' : (!exTable ? 'error' : (exams.length > 0 ? 'ok' : 'empty'));
            var res = {
              exams: exams,
              status: status,
              error: (!exTable && !isAuth) ? '未找到考试表格' : null
            };
            postToFlutter({ type: 'sync_exams_result', success: true, data: res });
            return JSON.stringify(res);
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
              var exDoc = null;
              var listHtml = await fetchHtmlAsync('/jsxsd/xsks/xsksap_list', 12000);
              if (checkAuth(null, listHtml, null)) {
                result.status.exams = 'not_logged_in';
              } else if (listHtml) {
                exDoc = new DOMParser().parseFromString(listHtml, 'text/html');
              }

              var hasExamTable = exDoc && findTableAcrossFrames(exDoc, function(d) {
                return d.getElementById('dataList') || findTableByKeywords(d, ['课程名称', '考试时间']);
              });

              if (result.status.exams !== 'not_logged_in' && !hasExamTable) {
                var queryHtml = await fetchHtmlAsync('/jsxsd/xsks/xsksap_query', 12000);
                if (checkAuth(null, queryHtml, null)) {
                  result.status.exams = 'not_logged_in';
                } else if (queryHtml) {
                  var qDoc = new DOMParser().parseFromString(queryHtml, 'text/html');
                  var iframeUrl = null;
                  var xnxqid = '';

                  var iframes = qDoc.querySelectorAll('iframe, frame');
                  for (var f = 0; f < iframes.length; f++) {
                    var src = iframes[f].getAttribute('src') || '';
                    if (src.indexOf('xsksap_list') !== -1 || src.indexOf('xsks') !== -1) {
                      iframeUrl = src;
                      break;
                    }
                  }

                  var sel = qDoc.querySelector('select[name="xnxqid"], #xnxqid, select');
                  if (sel) {
                    var opt = sel.querySelector('option[selected]');
                    if (opt && opt.value) {
                      xnxqid = opt.value.trim();
                    } else if (sel.selectedIndex >= 0 && sel.options && sel.options[sel.selectedIndex]) {
                      var sVal = (sel.options[sel.selectedIndex].value || '').trim();
                      if (sVal) {
                        xnxqid = sVal;
                      }
                    }
                  }

                  if (!xnxqid && result.weekInfo && result.weekInfo.semester) {
                    xnxqid = result.weekInfo.semester;
                  }
                  if (!xnxqid && result.gradesData && result.gradesData.grades && result.gradesData.grades.length > 0) {
                    var sems = result.gradesData.grades
                      .map(function(g) { return (g.semester || '').trim(); })
                      .filter(function(s) { return s.length > 0; })
                      .sort();
                    if (sems.length > 0) {
                      xnxqid = sems[sems.length - 1];
                    }
                  }

                  var listTargetUrl = iframeUrl;
                  if (listTargetUrl) {
                    if (listTargetUrl.indexOf('/') !== 0 && listTargetUrl.indexOf('http') !== 0) {
                      listTargetUrl = '/jsxsd/xsks/' + listTargetUrl;
                    }
                  } else {
                    listTargetUrl = '/jsxsd/xsks/xsksap_list' + (xnxqid ? ('?xnxqid=' + encodeURIComponent(xnxqid)) : '');
                  }

                  var secondaryHtml = await fetchHtmlAsync(listTargetUrl, 12000);
                  if (checkAuth(null, secondaryHtml, null)) {
                    result.status.exams = 'not_logged_in';
                  } else if (secondaryHtml) {
                    exDoc = new DOMParser().parseFromString(secondaryHtml, 'text/html');
                  }

                  if (result.status.exams !== 'not_logged_in' && (!exDoc || !exDoc.getElementById('dataList')) && xnxqid) {
                    var postHtml = await fetchHtmlAsyncPost('/jsxsd/xsks/xsksap_list', 'xnxqid=' + encodeURIComponent(xnxqid), 12000);
                    if (postHtml && !checkAuth(null, postHtml, null)) {
                      exDoc = new DOMParser().parseFromString(postHtml, 'text/html');
                    }
                  }
                }
              }

              // 仅当考试默认列表为空且当前正好在考试结果页 /jsxsd/xsks/ 时可回退检查 document
              if (result.status.exams !== 'not_logged_in' && (!exDoc || !findTableAcrossFrames(exDoc, function(d) {
                return d.getElementById('dataList') || findTableByKeywords(d, ['课程名称', '考试时间']);
              })) && currentUrl.indexOf('/jsxsd/xsks/') !== -1) {
                exDoc = document;
              }

              if (result.status.exams !== 'not_logged_in') {
                if (exDoc) {
                  if (checkAuth(exDoc, null, null)) {
                    result.status.exams = 'not_logged_in';
                  } else {
                    var exTable = findTableAcrossFrames(exDoc, function(d) {
                      return d.getElementById('dataList') || findTableByKeywords(d, ['课程名称', '考试时间']);
                    });
                    if (!exTable) {
                      result.status.exams = 'error';
                      result.errors.exams = '未找到考试表格(#dataList)，教务页面可能已改版';
                    } else {
                      result.exams = parseQiangZhiExams(exDoc);
                      result.status.exams = (result.exams && result.exams.length > 0) ? 'ok' : 'empty';
                    }
                  }
                } else if (result.status.exams !== 'error') {
                  result.status.exams = 'error';
                  result.errors.exams = '未能获取到考试列表页面文档';
                }
              }
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
      final courses = parseCoursesResult(data['courses']);
      final gradesResult = parseGradesResult(data['gradesData']);
      final exams = parseExamsResult(data['exams']);
      final weekInfo = parseWeekInfoResult(data['weekInfo']);

      final statusMap = data['status'] is Map ? data['status'] as Map : const {};
      final errorsMap = data['errors'] is Map ? data['errors'] as Map : const {};

      final statusCourses = SyncModuleStatus.fromString(
        statusMap['courses']?.toString(),
        fallbackOk: courses.isNotEmpty,
      );
      final statusGrades = SyncModuleStatus.fromString(
        statusMap['grades']?.toString(),
        fallbackOk: gradesResult.grades.isNotEmpty,
      );
      final statusExams = SyncModuleStatus.fromString(
        statusMap['exams']?.toString(),
        fallbackOk: exams.isNotEmpty,
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
      final courses = parseCoursesResult(data['courses']);
      final weekInfo = parseWeekInfoResult(data['weekInfo']);
      final statusStr = data['status']?.toString();
      final status = SyncModuleStatus.fromString(
        statusStr,
        fallbackOk: courses.isNotEmpty,
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

    List<GradeItem> grades = [];
    GradeSummary? summary;
    SyncModuleStatus status = SyncModuleStatus.empty;
    String? error;

    if (data is Map) {
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
      status = SyncModuleStatus.fromString(statusStr, fallbackOk: grades.isNotEmpty);
      error = data['error']?.toString();
    }

    return (grades: grades, summary: summary, status: status, error: error);
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

    final exams = parseExamsResult(data);
    final statusStr = data is Map ? data['status']?.toString() : null;
    final status = SyncModuleStatus.fromString(statusStr, fallbackOk: exams.isNotEmpty);
    final error = data is Map ? data['error']?.toString() : null;

    return (exams: exams, status: status, error: error);
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

  static SyncModuleStatus fromString(String? val, {bool fallbackOk = false}) {
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
        return fallbackOk ? SyncModuleStatus.ok : SyncModuleStatus.empty;
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
