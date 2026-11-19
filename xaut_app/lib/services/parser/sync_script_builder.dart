import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'exam_sync_script_fragment.dart';
import 'sync_script_fragments.dart';

/// 强智教务 WebView 注入脚本构建引擎
///
/// 职责单一：组装注入强智教务页面的 JavaScript 脚本（基础安全/桥接片段与考试穿透状态机
/// 已拆离至 [SyncScriptFragments] 与 [ExamSyncScriptFragment]，本类专注高层同步管线编排）。
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

  /// 顶层运行环境 Origin 白名单安全守卫（向后兼容透传）
  static const String originGuardJs = SyncScriptFragments.originGuardJs;

  /// 统一提取的统一身份认证 (CAS) 与登录状态检测函数常量（向后兼容透传）
  static const String checkAuthJs = SyncScriptFragments.checkAuthJs;

  /// 跨端原生消息桥接与异步 Fetch / 校历探测公共 JS 工具片段
  static String buildAsyncBridgeHelperJs({
    required String requestId,
    required int timeoutMs,
  }) {
    final safeRequestId = jsonEncode(requestId);
    return '''
      var reqId = $safeRequestId;
      var timeoutMs = $timeoutMs;
${SyncScriptFragments.bridgeRuntimeJs}
$checkAuthJs
${ExamSyncScriptFragment.examScheduleAsyncJs}
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
            if (checkAuth(document, null, currentUrl)) {
              result.status.courses = 'not_logged_in';
              result.status.grades = 'not_logged_in';
              result.status.exams = 'not_logged_in';
              postToFlutter({ type: 'sync_all_result', success: true, data: result });
              return JSON.stringify(result);
            }

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
