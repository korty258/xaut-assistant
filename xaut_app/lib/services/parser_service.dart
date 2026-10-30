import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models/course.dart';
import '../models/grade.dart';
import '../models/exam.dart';

class ParserService {
  static String? _cachedJsCode;

  /// 加载内置 assets 中的 qiangzhi_parser.js
  static Future<String> loadParserJs() async {
    if (_cachedJsCode != null) return _cachedJsCode!;
    _cachedJsCode = await rootBundle.loadString('assets/js/qiangzhi_parser.js');
    return _cachedJsCode!;
  }

  /// 构建课表解析注入代码
  static Future<String> buildCourseInjectionScript() async {
    final jsCode = await loadParserJs();
    return '''
      (function() {
        try {
          $jsCode
          var res = parseQiangZhiCourses(document);
          return JSON.stringify(res);
        } catch(e) {
          return JSON.stringify({ error: e.toString() });
        }
      })();
    ''';
  }

  /// 构建成绩解析注入代码
  static Future<String> buildGradesInjectionScript() async {
    final jsCode = await loadParserJs();
    return '''
      (function() {
        try {
          $jsCode
          var res = parseQiangZhiGrades(document);
          return JSON.stringify(res);
        } catch(e) {
          return JSON.stringify({ error: e.toString() });
        }
      })();
    ''';
  }

  /// 构建考试安排解析注入代码
  static Future<String> buildExamsInjectionScript() async {
    final jsCode = await loadParserJs();
    return '''
      (function() {
        try {
          $jsCode
          var res = parseQiangZhiExams(document);
          return JSON.stringify(res);
        } catch(e) {
          return JSON.stringify({ error: e.toString() });
        }
      })();
    ''';
  }

  /// 构建全量一键同步脚本 (课表 + 成绩 + 考试 跨模块一次性同步)
  static Future<String> buildSyncAllInjectionScript() async {
    final jsCode = await loadParserJs();
    return '''
      (function() {
        function fetchHtmlSync(url) {
          try {
            var xhr = new XMLHttpRequest();
            xhr.open('GET', url, false);
            xhr.send(null);
            if (xhr.status >= 200 && xhr.status < 300) {
              return xhr.responseText;
            }
          } catch(e) {}
          return null;
        }

        function fetchHtmlSyncPost(url, data) {
          try {
            var xhr = new XMLHttpRequest();
            xhr.open('POST', url, false);
            xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded; charset=UTF-8');
            xhr.send(data);
            if (xhr.status >= 200 && xhr.status < 300) {
              return xhr.responseText;
            }
          } catch(e) {}
          return null;
        }

        try {
          $jsCode

          var result = {
            courses: [],
            gradesData: { grades: [], summary: {} },
            exams: [],
            status: {
              courses: false,
              grades: false,
              exams: false
            }
          };

          var currentUrl = window.location.href;

          // 1. 课表解析
          try {
            if (currentUrl.indexOf('/jsxsd/xskb/') !== -1) {
              result.courses = parseQiangZhiCourses(document);
            } else {
              var kbHtml = fetchHtmlSync('/jsxsd/xskb/xskb_list.do');
              if (kbHtml) {
                var kbDoc = new DOMParser().parseFromString(kbHtml, 'text/html');
                result.courses = parseQiangZhiCourses(kbDoc);
              }
            }
            if (result.courses && result.courses.length > 0) {
              result.status.courses = true;
            }
          } catch(e) {}

          // 2. 成绩解析
          try {
            if (currentUrl.indexOf('/jsxsd/kscj/') !== -1) {
              result.gradesData = parseQiangZhiGrades(document);
            } else {
              var cjHtml = fetchHtmlSync('/jsxsd/kscj/cjcx_list');
              if (cjHtml) {
                var cjDoc = new DOMParser().parseFromString(cjHtml, 'text/html');
                result.gradesData = parseQiangZhiGrades(cjDoc);
              }
            }
            if (result.gradesData && result.gradesData.grades && result.gradesData.grades.length > 0) {
              result.status.grades = true;
            }
          } catch(e) {}

          // 3. 考试安排解析（深度穿透外壳页与参数自动提取）
          try {
            if (currentUrl.indexOf('/jsxsd/xsks/') !== -1) {
              result.exams = parseQiangZhiExams(document);
            } else {
              // 先抓取查询外壳页 /jsxsd/xsks/xsksap_query 获取当前激活学年学期及内嵌 iframe 真实请求参数
              var queryHtml = fetchHtmlSync('/jsxsd/xsks/xsksap_query');
              var iframeUrl = null;
              var xnxqid = '';

              if (queryHtml) {
                var qDoc = new DOMParser().parseFromString(queryHtml, 'text/html');

                // A. 优先直接提取 iframe 中的完整 src (通常自动包含真实参数如 ?xnxqid=2026-2027-1)
                var iframes = qDoc.querySelectorAll('iframe, frame');
                for (var f = 0; f < iframes.length; f++) {
                  var src = iframes[f].getAttribute('src') || '';
                  if (src.indexOf('xsksap_list') !== -1 || src.indexOf('xsks') !== -1) {
                    iframeUrl = src;
                    break;
                  }
                }

                // B. 提取学期参数 xnxqid
                var sel = qDoc.querySelector('select[name="xnxqid"], #xnxqid, select');
                if (sel) {
                  var opt = sel.querySelector('option[selected]') || sel.querySelector('option');
                  if (opt && opt.value) {
                    xnxqid = opt.value.trim();
                  }
                }
              }

              // 备用学期获取：从已抓到的成绩数据中提取最新学期
              if (!xnxqid && result.gradesData && result.gradesData.grades && result.gradesData.grades.length > 0) {
                xnxqid = result.gradesData.grades[0].semester || '';
              }

              // 构造完整的考试列表 URL
              var listTargetUrl = iframeUrl;
              if (listTargetUrl) {
                if (listTargetUrl.indexOf('/') !== 0 && listTargetUrl.indexOf('http') !== 0) {
                  listTargetUrl = '/jsxsd/xsks/' + listTargetUrl;
                }
              } else {
                listTargetUrl = '/jsxsd/xsks/xsksap_list' + (xnxqid ? ('?xnxqid=' + encodeURIComponent(xnxqid)) : '');
              }

              // 1. GET 请求目标列表页
              var listHtml = fetchHtmlSync(listTargetUrl);
              if (listHtml) {
                var listDoc = new DOMParser().parseFromString(listHtml, 'text/html');
                result.exams = parseQiangZhiExams(listDoc);
              }

              // 2. 若 GET 为空且具备 xnxqid，尝试 POST 请求
              if ((!result.exams || result.exams.length === 0) && xnxqid) {
                var postHtml = fetchHtmlSyncPost('/jsxsd/xsks/xsksap_list', 'xnxqid=' + encodeURIComponent(xnxqid));
                if (postHtml) {
                  var postDoc = new DOMParser().parseFromString(postHtml, 'text/html');
                  result.exams = parseQiangZhiExams(postDoc);
                }
              }

              // 3. 终极保底：无参数 GET
              if (!result.exams || result.exams.length === 0) {
                var fallbackHtml = fetchHtmlSync('/jsxsd/xsks/xsksap_list');
                if (fallbackHtml) {
                  var fbDoc = new DOMParser().parseFromString(fallbackHtml, 'text/html');
                  result.exams = parseQiangZhiExams(fbDoc);
                }
              }
            }

            if (result.exams && result.exams.length > 0) {
              result.status.exams = true;
            }
          } catch(e) {}

          return JSON.stringify(result);
        } catch(e) {
          return JSON.stringify({ error: e.toString() });
        }
      })();
    ''';
  }

  /// 统一处理 WebView 返回的全量同步结果
  static SyncAllResult parseSyncAllResult(dynamic rawResult) {
    if (rawResult == null) {
      return const SyncAllResult(
        courses: [],
        grades: [],
        exams: [],
        hasCourses: false,
        hasGrades: false,
        hasExams: false,
        error: '执行结果为空',
      );
    }

    dynamic data = rawResult;
    if (data is String) {
      try {
        data = jsonDecode(data);
        if (data is String) {
          data = jsonDecode(data);
        }
      } catch (e) {
        return SyncAllResult(
          courses: const [],
          grades: const [],
          exams: const [],
          hasCourses: false,
          hasGrades: false,
          hasExams: false,
          error: 'JSON反序列化失败: $e',
        );
      }
    }

    if (data is Map) {
      final courses = parseCoursesResult(data['courses']);
      final gradesResult = parseGradesResult(data['gradesData']);
      final exams = parseExamsResult(data['exams']);

      return SyncAllResult(
        courses: courses,
        grades: gradesResult.grades,
        gradeSummary: gradesResult.summary,
        exams: exams,
        hasCourses: courses.isNotEmpty,
        hasGrades: gradesResult.grades.isNotEmpty,
        hasExams: exams.isNotEmpty,
        error: data['error'] as String?,
      );
    }

    return const SyncAllResult(
      courses: [],
      grades: [],
      exams: [],
      hasCourses: false,
      hasGrades: false,
      hasExams: false,
    );
  }

  /// 统一处理 WebView 返回的执行结果为 Course 列表
  static List<Course> parseCoursesResult(dynamic rawResult) {
    if (rawResult == null) return [];

    dynamic data = rawResult;
    if (data is String) {
      try {
        data = jsonDecode(data);
        if (data is String) {
          data = jsonDecode(data);
        }
      } catch (e) {
        return [];
      }
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
  static ({List<GradeItem> grades, GradeSummary? summary}) parseGradesResult(dynamic rawResult) {
    if (rawResult == null) return (grades: <GradeItem>[], summary: null);

    dynamic data = rawResult;
    if (data is String) {
      try {
        data = jsonDecode(data);
        if (data is String) {
          data = jsonDecode(data);
        }
      } catch (e) {
        return (grades: <GradeItem>[], summary: null);
      }
    }

    List<GradeItem> grades = [];
    GradeSummary? summary;

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
    }

    return (grades: grades, summary: summary);
  }

  /// 统一处理 WebView 返回的考试安排执行结果
  static List<ExamItem> parseExamsResult(dynamic rawResult) {
    if (rawResult == null) return [];

    dynamic data = rawResult;
    if (data is String) {
      try {
        data = jsonDecode(data);
        if (data is String) {
          data = jsonDecode(data);
        }
      } catch (e) {
        return [];
      }
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

class SyncAllResult {
  final List<Course> courses;
  final List<GradeItem> grades;
  final GradeSummary? gradeSummary;
  final List<ExamItem> exams;
  final bool hasCourses;
  final bool hasGrades;
  final bool hasExams;
  final String? error;

  const SyncAllResult({
    required this.courses,
    required this.grades,
    this.gradeSummary,
    required this.exams,
    required this.hasCourses,
    required this.hasGrades,
    required this.hasExams,
    this.error,
  });

  bool get hasAnyData => hasCourses || hasGrades || hasExams;
}
