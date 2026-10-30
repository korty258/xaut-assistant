import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart' as af;
import 'package:webview_windows/webview_windows.dart' as win;

import '../models/course.dart';
import '../models/exam.dart';
import '../providers/schedule_provider.dart';
import '../providers/grades_provider.dart';
import '../providers/exams_provider.dart';
import '../services/parser_service.dart';

enum _NavDestination { home, timetable, grades, exams, other }

class WebViewLoginScreen extends StatefulWidget {
  const WebViewLoginScreen({super.key});

  @override
  State<WebViewLoginScreen> createState() => _WebViewLoginScreenState();
}

class _WebViewLoginScreenState extends State<WebViewLoginScreen> {
  static const String _defaultUrl = 'https://jwgl.xaut.edu.cn/';
  static const String _timetableUrl = 'https://jwgl.xaut.edu.cn/jsxsd/xskb/xskb_list.do';
  static const String _gradesUrl = 'https://jwgl.xaut.edu.cn/jsxsd/kscj/cjcx_list';
  static const String _examsUrl = 'https://jwgl.xaut.edu.cn/jsxsd/xsks/xsksap_query';

  bool _isWindows = false;
  bool _isInitialized = false;
  bool _isLoading = true;
  String _currentUrl = _defaultUrl;

  // Windows WebView 控制器
  final win.WebviewController _winController = win.WebviewController();

  // Android/移动端 WebView 控制器
  late final af.WebViewController _mobileController;

  @override
  void initState() {
    super.initState();
    _isWindows = !kIsWeb && Platform.isWindows;

    if (_isWindows) {
      _initWindowsWebView();
    } else {
      _initMobileWebView();
    }
  }

  /// 计算当前 URL 所属的业务模块目的地
  _NavDestination _getActiveDestination() {
    final url = _currentUrl.toLowerCase();
    if (url.contains('/xskb/')) {
      return _NavDestination.timetable;
    } else if (url.contains('/kscj/')) {
      return _NavDestination.grades;
    } else if (url.contains('/xsks/')) {
      return _NavDestination.exams;
    } else if (url.contains('jwgl.xaut.edu.cn') && (url.endsWith('.cn/') || url.contains('/framework/'))) {
      return _NavDestination.home;
    }
    return _NavDestination.other;
  }

  String _getDestinationLabel(_NavDestination dest) {
    switch (dest) {
      case _NavDestination.timetable:
        return '我的课表';
      case _NavDestination.grades:
        return '成绩查询';
      case _NavDestination.exams:
        return '考试安排';
      case _NavDestination.home:
        return '教务主页';
      case _NavDestination.other:
        return '其他页面';
    }
  }

  /// 获取当前页面专属同步操作的图标与文字
  ({IconData icon, String label}) _getCurrentPageSyncInfo() {
    final dest = _getActiveDestination();
    switch (dest) {
      case _NavDestination.timetable:
        return (icon: Icons.calendar_month, label: '同步当前课表');
      case _NavDestination.grades:
        return (icon: Icons.grade, label: '同步当前成绩');
      case _NavDestination.exams:
        return (icon: Icons.assignment, label: '同步当前考试');
      case _NavDestination.home:
      case _NavDestination.other:
        return (icon: Icons.auto_awesome, label: '识别当前页');
    }
  }

  Future<void> _initWindowsWebView() async {
    try {
      await _winController.initialize();
      _winController.url.listen((url) {
        if (mounted) {
          setState(() {
            _currentUrl = url;
          });
        }
      });
      _winController.loadingState.listen((state) {
        if (mounted) {
          setState(() {
            _isLoading = state == win.LoadingState.loading;
          });
        }
      });
      await _winController.loadUrl(_defaultUrl);
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Windows WebView2 初始化失败: $e')),
        );
      }
    }
  }

  void _initMobileWebView() {
    _mobileController = af.WebViewController()
      ..setJavaScriptMode(af.JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        af.NavigationDelegate(
          onPageStarted: (url) {
            if (mounted) {
              setState(() {
                _isLoading = true;
                _currentUrl = url;
              });
            }
          },
          onPageFinished: (url) {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _currentUrl = url;
              });
            }
          },
          onWebResourceError: (err) {
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(_defaultUrl));

    setState(() {
      _isInitialized = true;
    });
  }

  /// 导航到指定 URL
  Future<void> _navigateTo(String url) async {
    if (_isWindows) {
      await _winController.loadUrl(url);
    } else {
      await _mobileController.loadRequest(Uri.parse(url));
    }
  }

  /// 执行一键全量同步（同时同步 课表 + 成绩 + 考试 3大模块）
  Future<void> _syncAll() async {
    final scheduleProvider = context.read<ScheduleProvider>();
    final gradesProvider = context.read<GradesProvider>();
    final examsProvider = context.read<ExamsProvider>();

    setState(() => _isLoading = true);

    try {
      final script = await ParserService.buildSyncAllInjectionScript();
      dynamic rawResult;

      if (_isWindows) {
        rawResult = await _winController.executeScript(script);
      } else {
        rawResult = await _mobileController.runJavaScriptReturningResult(script);
      }

      final result = ParserService.parseSyncAllResult(rawResult);

      if (!mounted) return;

      if (result.hasAnyData) {
        if (result.hasCourses) {
          await scheduleProvider.updateCourses(result.courses);
        }
        if (result.hasGrades) {
          await gradesProvider.updateGrades(result.grades, result.gradeSummary);
        }
        if (result.hasExams) {
          await examsProvider.updateExams(result.exams);
        }

        if (!mounted) return;

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.cloud_done_rounded, color: Colors.green, size: 36),
            title: const Text('全量教务同步完成'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSyncResultRow(
                  icon: Icons.calendar_month,
                  title: '课表数据',
                  detail: result.hasCourses ? '成功导入 ${result.courses.length} 门课程' : '未查询到课表数据',
                  isSuccess: result.hasCourses,
                ),
                const SizedBox(height: 10),
                _buildSyncResultRow(
                  icon: Icons.grade,
                  title: '学业成绩',
                  detail: result.hasGrades
                      ? '成功导入 ${result.grades.length} 门成绩 (GPA: ${result.gradeSummary?.averageGpa ?? "-"})'
                      : '未查询到成绩数据',
                  isSuccess: result.hasGrades,
                ),
                const SizedBox(height: 10),
                _buildSyncResultRow(
                  icon: Icons.assignment,
                  title: '考试日程',
                  detail: result.hasExams ? '成功导入 ${result.exams.length} 门考试安排' : '暂无已发布的考试安排',
                  isSuccess: result.hasExams,
                ),
              ],
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pop();
                },
                child: const Text('返回主页查看'),
              ),
            ],
          ),
        );
      } else {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 36),
            title: const Text('未同步到有效数据'),
            content: const Text(
              '未能从强智教务系统获取到课表、成绩或考试数据。\n\n'
              '操作指引：\n'
              '1. 请先在下方网页中输入学号与密码完成统一身份认证登录；\n'
              '2. 登录成功后，直接点击底部【一键同步全部】；\n'
              '3. 客户端将全自动穿透并提取三大教务模块！',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('我知道了'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('全量同步异常: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 自动识别当前网页并执行对应同步
  Future<void> _syncCurrentPage() async {
    final dest = _getActiveDestination();
    switch (dest) {
      case _NavDestination.timetable:
        await _syncSchedule();
        break;
      case _NavDestination.grades:
        await _syncGrades();
        break;
      case _NavDestination.exams:
        await _syncExams();
        break;
      case _NavDestination.home:
      case _NavDestination.other:
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.auto_awesome, color: Colors.blue),
                SizedBox(width: 8),
                Text('智能识别提示'),
              ],
            ),
            content: Text(
              '当前浏览页面为：${_getDestinationLabel(dest)}\n\n'
              '当前未处于课表、成绩或考试的特定功能页。\n\n'
              '建议：\n'
              '• 直接点击左侧【一键同步全部】在后台一次性全部提取；\n'
              '• 或点击上方快捷跳转进入对应页面后再单独同步。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _syncAll();
                },
                child: const Text('一键同步全部'),
              ),
            ],
          ),
        );
        break;
    }
  }

  Widget _buildSyncResultRow({
    required IconData icon,
    required String title,
    required String detail,
    required bool isSuccess,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isSuccess ? Icons.check_circle : Icons.remove_circle_outline,
          color: isSuccess ? Colors.green : Colors.grey,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: TextStyle(
                  fontSize: 12,
                  color: isSuccess ? Colors.black87 : Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 执行一键解析并同步课表
  Future<void> _syncSchedule() async {
    final scheduleProvider = context.read<ScheduleProvider>();
    setState(() => _isLoading = true);

    try {
      final script = await ParserService.buildCourseInjectionScript();
      dynamic rawResult;

      if (_isWindows) {
        rawResult = await _winController.executeScript(script);
      } else {
        rawResult = await _mobileController.runJavaScriptReturningResult(script);
      }

      final List<Course> parsed = ParserService.parseCoursesResult(rawResult);

      if (!mounted) return;

      if (parsed.isNotEmpty) {
        await scheduleProvider.updateCourses(parsed);
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('课表同步成功'),
              ],
            ),
            content: Text('成功解析并导入 ${parsed.length} 门课程！'),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pop();
                },
                child: const Text('返回课表查看'),
              ),
            ],
          ),
        );
      } else {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange),
                SizedBox(width: 8),
                Text('未检测到课表'),
              ],
            ),
            content: const Text(
              '当前页面未识别到课程表格 (table#timetable 或 table#kbtable)。\n\n'
              '操作提示：\n'
              '1. 请先在下方网页中完成统一身份认证登录；\n'
              '2. 登录成功后，点击上方导航条中的【我的课表】按钮；\n'
              '3. 待课表页面完整加载后，再次点击【同步当前课表】！',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('我知道了'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _navigateTo(_timetableUrl);
                },
                child: const Text('前往我的课表'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('解析执行异常: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 执行一键解析并同步成绩
  Future<void> _syncGrades() async {
    final gradesProvider = context.read<GradesProvider>();
    setState(() => _isLoading = true);

    try {
      final script = await ParserService.buildGradesInjectionScript();
      dynamic rawResult;

      if (_isWindows) {
        rawResult = await _winController.executeScript(script);
      } else {
        rawResult = await _mobileController.runJavaScriptReturningResult(script);
      }

      final result = ParserService.parseGradesResult(rawResult);

      if (!mounted) return;

      if (result.grades.isNotEmpty) {
        await gradesProvider.updateGrades(result.grades, result.summary);
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('成绩同步成功'),
              ],
            ),
            content: Text(
              '成功导入 ${result.grades.length} 门课程成绩！\n'
              '平均 GPA: ${result.summary?.averageGpa ?? '-'}\n'
              '总修学分: ${result.summary?.totalCredits ?? '-'}',
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pop();
                },
                child: const Text('返回查看成绩'),
              ),
            ],
          ),
        );
      } else {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange),
                SizedBox(width: 8),
                Text('未检测到成绩表格'),
              ],
            ),
            content: const Text(
              '当前页面未识别到成绩表格。\n\n'
              '操作提示：\n'
              '请先点击上方快捷栏中的【成绩查询】按钮，跳转至成绩列表页后再执行同步。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('我知道了'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _navigateTo(_gradesUrl);
                },
                child: const Text('前往成绩查询'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('成绩解析异常: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 执行一键解析并同步考试安排
  Future<void> _syncExams() async {
    final examsProvider = context.read<ExamsProvider>();
    setState(() => _isLoading = true);

    try {
      final script = await ParserService.buildExamsInjectionScript();
      dynamic rawResult;

      if (_isWindows) {
        rawResult = await _winController.executeScript(script);
      } else {
        rawResult = await _mobileController.runJavaScriptReturningResult(script);
      }

      final List<ExamItem> parsed = ParserService.parseExamsResult(rawResult);

      if (!mounted) return;

      if (parsed.isNotEmpty) {
        await examsProvider.updateExams(parsed);
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('考试日程同步成功'),
              ],
            ),
            content: Text('成功解析导入 ${parsed.length} 门考试日程！已自动提取考场与座位号。'),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pop();
                },
                child: const Text('返回查看考试'),
              ),
            ],
          ),
        );
      } else {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange),
                SizedBox(width: 8),
                Text('未检测到考试表格'),
              ],
            ),
            content: const Text(
              '当前页面未识别到考试安排数据。\n\n'
              '操作提示：\n'
              '请先点击上方快捷栏中的【考试安排】按钮，跳转至考试查询页后再执行同步。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('我知道了'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _navigateTo(_examsUrl);
                },
                child: const Text('前往考试安排'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('考试解析异常: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    if (_isWindows) {
      _winController.dispose();
    }
    super.dispose();
  }

  Widget _buildNavChip({
    required IconData icon,
    required String label,
    required _NavDestination destination,
    required String targetUrl,
    required _NavDestination activeNav,
    required ThemeData theme,
  }) {
    final isSelected = destination == activeNav;

    return ActionChip(
      avatar: Icon(
        icon,
        size: 16,
        color: isSelected ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurfaceVariant,
      ),
      label: Text(label),
      backgroundColor: isSelected ? theme.colorScheme.primaryContainer : theme.colorScheme.surface,
      side: BorderSide(
        color: isSelected
            ? theme.colorScheme.primary.withValues(alpha: 0.6)
            : Colors.grey.withValues(alpha: 0.25),
        width: isSelected ? 1.5 : 1.0,
      ),
      labelStyle: TextStyle(
        color: isSelected ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurface,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      onPressed: () => _navigateTo(targetUrl),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeNav = _getActiveDestination();
    final pageSyncInfo = _getCurrentPageSyncInfo();

    return Scaffold(
      appBar: AppBar(
        title: const Text('强智教务登录与同步', style: TextStyle(fontSize: 16)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4.0),
          child: _isLoading
              ? const LinearProgressIndicator()
              : const SizedBox(height: 4.0),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新页面',
            onPressed: () {
              if (_isWindows) {
                _winController.reload();
              } else {
                _mobileController.reload();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: '关闭',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: Column(
        children: [
          // 快捷模块导航条 (根据当前页面动态自适应高亮)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Text('快捷跳转: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 6),
                  _buildNavChip(
                    icon: Icons.home_rounded,
                    label: '教务主页',
                    destination: _NavDestination.home,
                    targetUrl: _defaultUrl,
                    activeNav: activeNav,
                    theme: theme,
                  ),
                  const SizedBox(width: 6),
                  _buildNavChip(
                    icon: Icons.calendar_month_rounded,
                    label: '我的课表',
                    destination: _NavDestination.timetable,
                    targetUrl: _timetableUrl,
                    activeNav: activeNav,
                    theme: theme,
                  ),
                  const SizedBox(width: 6),
                  _buildNavChip(
                    icon: Icons.grade_rounded,
                    label: '成绩查询',
                    destination: _NavDestination.grades,
                    targetUrl: _gradesUrl,
                    activeNav: activeNav,
                    theme: theme,
                  ),
                  const SizedBox(width: 6),
                  _buildNavChip(
                    icon: Icons.assignment_rounded,
                    label: '考试安排',
                    destination: _NavDestination.exams,
                    targetUrl: _examsUrl,
                    activeNav: activeNav,
                    theme: theme,
                  ),
                ],
              ),
            ),
          ),

          // 当前地址提示
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            color: Colors.grey.withValues(alpha: 0.08),
            child: Row(
              children: [
                Icon(Icons.link, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _currentUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ),
              ],
            ),
          ),

          // WebView 渲染区域
          Expanded(
            child: !_isInitialized
                ? const Center(child: CircularProgressIndicator())
                : _isWindows
                    ? win.Webview(_winController)
                    : af.WebViewWidget(controller: _mobileController),
          ),

          // 底部常驻同步操作按钮栏
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // 1. 默认主选项：一键同步全部 (课表/成绩/考试 一次搞定)
                  Expanded(
                    flex: 6,
                    child: FilledButton.icon(
                      onPressed: _isLoading ? null : _syncAll,
                      icon: const Icon(Icons.cloud_sync_rounded),
                      label: const Text(
                        '一键同步全部',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // 2. 自动识别当前页，点击实现对应专项同步
                  Expanded(
                    flex: 5,
                    child: FilledButton.tonalIcon(
                      onPressed: _isLoading ? null : _syncCurrentPage,
                      icon: Icon(pageSyncInfo.icon, size: 18),
                      label: Text(
                        pageSyncInfo.label,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
