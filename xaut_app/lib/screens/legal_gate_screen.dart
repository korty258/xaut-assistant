import 'dart:async';
import 'dart:io' show Platform, exit;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/exams_provider.dart';
import '../providers/grades_provider.dart';
import '../providers/schedule_provider.dart';
import '../services/legal_service.dart';
import '../utils/date_time_utils.dart';
import '../widgets/diagnostics_dialog.dart';
import '../widgets/legal/legal_markdown_reader.dart';
import '../widgets/legal/legal_revoke_dialogs.dart';
import 'home_screen.dart';

/// 首次启动法律门禁与条款查阅页面
class LegalGateScreen extends StatefulWidget {
  final bool isGate;
  final int initialDocIndex;

  const LegalGateScreen({
    super.key,
    this.isGate = true,
    this.initialDocIndex = 0,
  });

  @override
  State<LegalGateScreen> createState() => _LegalGateScreenState();
}

class _LegalGateScreenState extends State<LegalGateScreen> {
  int _selectedDoc = 0;
  bool _agreed = false;
  bool _isLoading = true;

  DateTime? _acceptedAt;
  String? _acceptedVersion;

  final Map<int, String> _docTexts = {};
  late final List<ScrollController> _scrollControllers;
  late final List<bool> _docsRead;
  late final List<LegalDocItem> _docs;

  bool get _allDocsRead => _docsRead.every((r) => r);
  int get _unreadCount => _docsRead.where((r) => !r).length;

  @override
  void initState() {
    super.initState();
    _docs = widget.isGate
        ? const [
            (title: '用户协议', assetPath: 'assets/legal/terms_of_service.md'),
            (title: '隐私政策', assetPath: 'assets/legal/privacy_policy.md'),
            (title: '免责声明', assetPath: 'assets/legal/disclaimer.md'),
          ]
        : const [
            (title: '用户协议', assetPath: 'assets/legal/terms_of_service.md'),
            (title: '隐私政策', assetPath: 'assets/legal/privacy_policy.md'),
            (title: '免责声明', assetPath: 'assets/legal/disclaimer.md'),
            (title: '开源致谢', assetPath: 'assets/legal/third_party_notices.md'),
          ];
    _selectedDoc = widget.initialDocIndex.clamp(0, _docs.length - 1);
    _docsRead = List.generate(_docs.length, (_) => !widget.isGate);
    _scrollControllers = List.generate(_docs.length, (index) {
      final ctrl = ScrollController();
      if (widget.isGate) {
        ctrl.addListener(() => _checkScrollProgress(index));
      }
      return ctrl;
    });
    unawaited(_initData());
  }

  void _checkScrollProgress(int index) {
    if (!widget.isGate || _docsRead[index]) return;
    if (index >= _scrollControllers.length) return;
    final controller = _scrollControllers[index];
    if (!controller.hasClients) return;

    final position = controller.position;
    if (position.maxScrollExtent <= 10 ||
        position.pixels >= position.maxScrollExtent - 32) {
      if (mounted) {
        setState(() {
          _docsRead[index] = true;
        });
      }
    }
  }

  void _switchDoc(int newIndex) {
    setState(() {
      _selectedDoc = newIndex;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _checkScrollProgress(newIndex);
    });
  }

  @override
  void dispose() {
    for (final ctrl in _scrollControllers) {
      ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _initData() async {
    for (int i = 0; i < _docs.length; i++) {
      try {
        final text = await rootBundle.loadString(_docs[i].assetPath);
        _docTexts[i] = text;
      } on Object catch (e) {
        _docTexts[i] = '加载 ${_docs[i].title} 失败: $e';
      }
    }

    if (!widget.isGate) {
      _acceptedAt = await LegalService.getAcceptedAt();
      _acceptedVersion = await LegalService.getAcceptedVersion();
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        for (int i = 0; i < _docs.length; i++) {
          _checkScrollProgress(i);
        }
      });
    }
  }

  Future<void> _onAgree() async {
    if (!_agreed) return;
    await LegalService.accept();
    if (mounted) {
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  Future<void> _onDisagree() async {
    final confirmed = await LegalRevokeDialogs.confirmDisagree(context);
    if (confirmed == true) {
      if (!kIsWeb && Platform.isAndroid) {
        await SystemNavigator.pop();
      } else {
        exit(0);
      }
    }
  }

  Future<void> _onRevokeConsent() async {
    final confirmed = await LegalRevokeDialogs.confirmRevokeConsent(context);
    if (confirmed == true) {
      await _executeRevokeCleanup();
    }
  }

  void _navigateToFreshGate() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LegalGateScreen(isGate: true)),
      (_) => false,
    );
  }

  Future<void> _executeRevokeCleanup() async {
    if (mounted) {
      ScheduleProvider? sp;
      GradesProvider? gp;
      ExamsProvider? ep;
      try { sp = context.read<ScheduleProvider>(); } on Object catch (_) {}
      try { gp = context.read<GradesProvider>(); } on Object catch (_) {}
      try { ep = context.read<ExamsProvider>(); } on Object catch (_) {}
      try { await sp?.clearAll(); } on Object catch (_) {}
      try { await gp?.clearAll(); } on Object catch (_) {}
      try { await ep?.clearAll(); } on Object catch (_) {}
    }

    final cleanupResult = await LegalService.revokeAndClearAll();
    if (!mounted) return;

    final isWindows = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

    if (cleanupResult.isFullyCleaned) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已成功撤回授权并彻底销毁所有本地数据与密钥'),
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _navigateToFreshGate();
      return;
    }

    if (!cleanupResult.hasUnqueuedFailures &&
        cleanupResult.hasPendingColdStartWipe) {
      final queuedNames = <String>[];
      if (cleanupResult.masterKeyPendingQueued) {
        queuedNames.add('主加密密钥');
      }
      if (cleanupResult.windowsPendingQueued) {
        queuedNames.add('Windows 本地缓存目录');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已撤回同意并清空本地偏好设置。${queuedNames.join('、')}已加入待清理队列，将在下次应用启动时自动补偿擦除。',
          ),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _navigateToFreshGate();
      return;
    }

    final action = await LegalRevokeDialogs.showPartialCleanupDialog(
      context,
      cleanupResult: cleanupResult,
      isWindows: isWindows,
    );

    if (!mounted) return;
    if (action == 'retry') {
      await _executeRevokeCleanup();
    } else if (action == 'gate') {
      _navigateToFreshGate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWide = MediaQuery.of(context).size.width >= 720;

    return Scaffold(
      appBar: widget.isGate
          ? null
          : AppBar(
              title: const Text('法律条款与合规声明'),
              centerTitle: false,
              actions: [
                TextButton.icon(
                  onPressed: () => showJinhuaLicensePage(context),
                  icon: const Icon(Icons.policy_outlined, size: 18),
                  label: const Text(
                    '开源许可库',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
                TextButton.icon(
                  onPressed: _onRevokeConsent,
                  icon: Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: theme.colorScheme.error,
                  ),
                  label: Text(
                    '撤回同意',
                    style: TextStyle(
                      color: theme.colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isWide ? 840 : double.infinity),
            child: Column(
              children: [
                _buildHeader(theme),
                LegalDocSelector(
                  docs: _docs,
                  docsRead: _docsRead,
                  selectedDoc: _selectedDoc,
                  isGate: widget.isGate,
                  onSelect: _switchDoc,
                ),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : LegalMarkdownReader(
                          docs: _docs,
                          docsRead: _docsRead,
                          scrollControllers: _scrollControllers,
                          docTexts: _docTexts,
                          selectedDoc: _selectedDoc,
                          isGate: widget.isGate,
                          onSwitchDoc: _switchDoc,
                        ),
                ),
                if (widget.isGate)
                  _buildGateConsentBar(theme)
                else
                  _buildReaderFooter(theme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/logo.png',
                  width: 44,
                  height: 44,
                  errorBuilder: (_, _, _) => const Icon(Icons.school, size: 40),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '金花助手',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.tertiaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '非官方 · GPL-3.0',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onTertiaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '适用于西安理工大学学生的课表工具',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '使用前重要须知（请特别关注免责条款）',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                _buildBulletText(
                  '本软件为在校学生个人开发的非官方开源工具，与西安理工大学无任何隶属、合作、代理或授权关系。',
                  theme,
                ),
                _buildBulletText(
                  '账号密码仅在学校官方登录页输入，本软件不读取、不上传；数据仅保存在本机设备。',
                  theme,
                ),
                _buildBulletText(
                  '课表、成绩、GPA、考试倒计时均为本地解析或估算，仅供参考，以官方教务为准。',
                  theme,
                ),
                _buildBulletText(
                  '请合理使用，严禁高频批量抓取或实施任何影响学校教务系统正常运行的行为。',
                  theme,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBulletText(String text, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '• ',
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGateConsentBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _allDocsRead
                  ? Colors.green.withValues(alpha: 0.1)
                  : theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _allDocsRead
                    ? Colors.green.withValues(alpha: 0.4)
                    : theme.colorScheme.primary.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _allDocsRead ? Icons.verified_rounded : Icons.info_outline_rounded,
                  size: 16,
                  color: _allDocsRead ? Colors.green : theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _allDocsRead
                        ? '全部文书已完整阅读完毕，请勾选下方确认后开始使用'
                        : '请完整滑动阅读全部 3 份条款至底部以解锁同意（还剩 $_unreadCount 份待阅读）',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _allDocsRead
                          ? Colors.green
                          : theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: _allDocsRead
                ? () {
                    setState(() {
                      _agreed = !_agreed;
                    });
                  }
                : () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '请先完整滑动阅读全部 3 份条款至底部（还剩 $_unreadCount 份待阅读）',
                        ),
                        duration: const Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Checkbox(
                    value: _agreed,
                    onChanged: _allDocsRead
                        ? (val) {
                            setState(() {
                              _agreed = val ?? false;
                            });
                          }
                        : null,
                  ),
                  Expanded(
                    child: Text(
                      '我已完整阅读并同意《用户协议》《隐私政策》与《免责声明》，并充分理解其中的免责与责任限制条款。',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _allDocsRead
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: OutlinedButton(
                  onPressed: _onDisagree,
                  child: const Text('不同意，退出'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: FilledButton(
                  onPressed: (_agreed && _allDocsRead) ? _onAgree : null,
                  child: const Text('同意并继续'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReaderFooter(ThemeData theme) {
    final dateStr = _acceptedAt != null
        ? DateTimeUtils.formatFullDateTime(_acceptedAt).substring(0, 16)
        : '未记录';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: () => DiagnosticsDialog.show(context),
                icon: const Icon(Icons.bug_report_outlined, size: 16),
                label: const Text('查看并复制诊断摘要'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  textStyle: const TextStyle(fontSize: 12),
                ),
                onPressed: () => DiagnosticsDialog.copyIssuesUrl(context),
                icon: const Icon(Icons.link_rounded, size: 16),
                label: const Text('复制开源仓库 / 问题反馈地址'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.verified_outlined,
                size: 15,
                color: Colors.green.shade700,
              ),
              const SizedBox(width: 6),
              Text(
                '本地签署存证：已于 $dateStr 同意（版本 ${_acceptedVersion ?? LegalService.currentVersion}）',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '开发者：korty258 ｜ 异议与反馈联系邮箱：korty666@outlook.com',
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
