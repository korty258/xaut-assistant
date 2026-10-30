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

  /// 跨页面补充探测周次与校历开学日的公共 JS 片段
  static const String _xhrWeekFallbackJs = '''
    function resolveTeachingWeekWithFallback(doc, currentUrl) {
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
        var html = fetchHtmlSync(probeUrls[i]);
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
      var calHtml = fetchHtmlSync('/jsxsd/jxzl/jxzl_query');
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

      return info;
    }
  ''';

  /// 构建轻量级当前教学周被动嗅探脚本（供教务主页加载完成时静默捕获右上角「2026-2027-1 第9周」）
  static Future<String> buildWeekDetectScript() async {
    final jsCode = await loadParserJs();
    return '''
      (function() {
        try {
          $jsCode
          var allowSelect = window.location.href.indexOf('/jsxsd/xskb/') === -1;
          var info = parseQiangZhiTeachingWeek(document, allowSelect);
          return JSON.stringify(info);
        } catch(e) {
          return JSON.stringify({ error: e.toString() });
        }
      })();
    ''';
  }

  /// 构建课表解析注入代码（顺带提取当前教学周次与学期）
  static Future<String> buildCourseInjectionScript() async {
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

        try {
          $jsCode
          $_xhrWeekFallbackJs
          var courses = parseQiangZhiCourses(document);
          var weekInfo = resolveTeachingWeekWithFallback(document, window.location.href);
          return JSON.stringify({
            courses: courses,
            weekInfo: weekInfo
          });
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

  /// 构建全量一键同步脚本 (课表 + 成绩 + 考试 + 当前教学周 跨模块一次性同步)
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
          $_xhrWeekFallbackJs

          var result = {
            courses: [],
            gradesData: { grades: [], summary: {} },
            exams: [],
            weekInfo: { currentWeek: null, semester: '', semesterStartDate: '' },
            status: {
              courses: false,
              grades: false,
              exams: false
            }
          };

          var currentUrl = window.location.href;

          // 0. 提取当前教学周与学年学期（教务主页右上角天然带有 "2026-2027-1 第9周"）
          try {
            result.weekInfo = resolveTeachingWeekWithFallback(document, currentUrl);
          } catch(e) {}

          // 1. 课表解析
          try {
            if (currentUrl.indexOf('/jsxsd/xskb/') !== -1) {
              result.courses = parseQiangZhiCourses(document);
            } else {
              var kbHtml = fetchHtmlSync('/jsxsd/xskb/xskb_list.do');
              if (kbHtml) {
                var kbDoc = new DOMParser().parseFromString(kbHtml, 'text/html');
                result.courses = parseQiangZhiCourses(kbDoc);
                if (!result.weekInfo.semester) {
                  var kbSem = parseQiangZhiTeachingWeek(kbDoc, false);
                  if (kbSem && kbSem.semester) {
                    result.weekInfo.semester = kbSem.semester;
                  }
                }
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

              // 备用学期获取：从已识别学期或成绩数据中提取最新学期
              if (!xnxqid && result.weekInfo && result.weekInfo.semester) {
                xnxqid = result.weekInfo.semester;
              }
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
        hasCourses: false,
        hasGrades: false,
        hasExams: false,
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
        hasCourses: false,
        hasGrades: false,
        hasExams: false,
        error: 'JSON反序列化失败: $e',
      );
    }

    if (data is Map) {
      final courses = parseCoursesResult(data['courses']);
      final gradesResult = parseGradesResult(data['gradesData']);
      final exams = parseExamsResult(data['exams']);
      final weekInfo = parseWeekInfoResult(data['weekInfo']);

      return SyncAllResult(
        courses: courses,
        grades: gradesResult.grades,
        gradeSummary: gradesResult.summary,
        exams: exams,
        hasCourses: courses.isNotEmpty,
        hasGrades: gradesResult.grades.isNotEmpty,
        hasExams: exams.isNotEmpty,
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
      hasCourses: false,
      hasGrades: false,
      hasExams: false,
    );
  }

  /// 统一处理单页课表同步结果（同时包含课程列表与自动识别的周次）
  static ({
    List<Course> courses,
    int? detectedWeek,
    String? detectedSemester,
    DateTime? detectedSemesterStart,
  }) parseCourseSyncResult(dynamic rawResult) {
    if (rawResult == null) {
      return (
        courses: <Course>[],
        detectedWeek: null,
        detectedSemester: null,
        detectedSemesterStart: null,
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
      );
    }

    if (data is Map) {
      final courses = parseCoursesResult(data['courses']);
      final weekInfo = parseWeekInfoResult(data['weekInfo']);
      return (
        courses: courses,
        detectedWeek: weekInfo.currentWeek,
        detectedSemester: weekInfo.semester,
        detectedSemesterStart: weekInfo.semesterStartDate,
      );
    }

    return (
      courses: parseCoursesResult(data),
      detectedWeek: null,
      detectedSemester: null,
      detectedSemesterStart: null,
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
  static ({List<GradeItem> grades, GradeSummary? summary}) parseGradesResult(dynamic rawResult) {
    if (rawResult == null) return (grades: <GradeItem>[], summary: null);

    dynamic data;
    try {
      data = _unwrapJson(rawResult);
    } catch (_) {
      return (grades: <GradeItem>[], summary: null);
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

class SyncAllResult {
  final List<Course> courses;
  final List<GradeItem> grades;
  final GradeSummary? gradeSummary;
  final List<ExamItem> exams;
  final bool hasCourses;
  final bool hasGrades;
  final bool hasExams;
  final int? detectedWeek;
  final String? detectedSemester;
  final DateTime? detectedSemesterStart;
  final String? error;

  const SyncAllResult({
    required this.courses,
    required this.grades,
    this.gradeSummary,
    required this.exams,
    required this.hasCourses,
    required this.hasGrades,
    required this.hasExams,
    this.detectedWeek,
    this.detectedSemester,
    this.detectedSemesterStart,
    this.error,
  });

  bool get hasAnyData => hasCourses || hasGrades || hasExams;
}
