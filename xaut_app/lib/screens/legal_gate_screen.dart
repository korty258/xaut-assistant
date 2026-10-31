import 'dart:io' show Platform, exit;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../services/legal_service.dart';
import 'home_screen.dart';

/// 首次启动法律门禁与条款查阅页面
class LegalGateScreen extends StatefulWidget {
  /// 是否作为强制准入门禁模式。
  /// true: 首次启动/版本更新门禁，包含强制勾选与退出确认；
  /// false: 从关于页查阅模式，供浏览条款、查看签署存证与撤回同意。
  final bool isGate;

  /// 默认选中的文档类型：0 = 用户协议, 1 = 隐私政策, 2 = 免责声明
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

  /// 记录各文书是否已滑动阅读完毕（门禁模式下需 3 份全部读完）
  late final List<bool> _docsRead;

  bool get _allDocsRead => _docsRead.every((r) => r);
  int get _unreadCount => _docsRead.where((r) => !r).length;

  final List<({String title, String assetPath})> _docs = const [
    (title: '用户协议', assetPath: 'assets/legal/terms_of_service.md'),
    (title: '隐私政策', assetPath: 'assets/legal/privacy_policy.md'),
    (title: '免责声明', assetPath: 'assets/legal/disclaimer.md'),
  ];

  @override
  void initState() {
    super.initState();
    _selectedDoc = widget.initialDocIndex.clamp(0, _docs.length - 1);
    _docsRead = List.generate(_docs.length, (_) => !widget.isGate);
    _scrollControllers = List.generate(_docs.length, (index) {
      final ctrl = ScrollController();
      if (widget.isGate) {
        ctrl.addListener(() => _checkScrollProgress(index));
      }
      return ctrl;
    });
    _initData();
  }

  void _checkScrollProgress(int index) {
    if (!widget.isGate || _docsRead[index]) return;
    if (index >= _scrollControllers.length) return;
    final controller = _scrollControllers[index];
    if (!controller.hasClients) return;

    final position = controller.position;
    // 当文档高度不需要滚动（内容全部展示），或已滑动到接近末尾（距底 <= 32 像素）时标记为读完
    if (position.maxScrollExtent <= 10 || position.pixels >= position.maxScrollExtent - 32) {
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
      } catch (e) {
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
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  Future<void> _onDisagree() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, size: 36, color: Colors.orange),
        title: const Text('退出应用'),
        content: const Text(
          '如您不同意《用户协议》《隐私政策》或《免责声明》，将无法使用本软件。点击“确定退出”将关闭本应用。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('返回阅读'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确定退出'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (!kIsWeb && Platform.isAndroid) {
        await SystemNavigator.pop();
      } else {
        exit(0);
      }
    }
  }

  Future<void> _onRevokeConsent() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.delete_forever_rounded, size: 36, color: Theme.of(ctx).colorScheme.error),
        title: const Text('撤回同意并清空数据？'),
        content: const Text(
          '依据《个人信息保护法》第 15 条，您有权撤回同意。\n\n'
          '撤回同意后，本软件将彻底清除保存在本机设备上的所有课表、成绩、考试数据以及授权凭证，并退回首次启动法律门禁。\n\n'
          '此操作不可撤销，确定撤回吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确定撤回并清空'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await LegalService.revokeAndClearAll();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LegalGateScreen(isGate: true)),
          (_) => false,
        );
      }
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
                  onPressed: _onRevokeConsent,
                  icon: Icon(Icons.delete_outline, size: 18, color: theme.colorScheme.error),
                  label: Text(
                    '撤回同意',
                    style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
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
                _buildDocSelector(theme),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _buildDocReader(theme),
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

  /// 顶栏：应用图标、名称、副标题与要点告知卡片
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
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
          // 4项核心法务要点告知卡片
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
                    Icon(Icons.info_outline_rounded, size: 16, color: theme.colorScheme.primary),
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
                _buildBulletText('本软件为在校学生个人开发的非官方开源工具，与西安理工大学无任何隶属、合作、代理或授权关系。', theme),
                _buildBulletText('账号密码仅在学校官方登录页输入，本软件不读取、不上传；数据仅保存在本机设备。', theme),
                _buildBulletText('课表、成绩、GPA、考试倒计时均为本地解析或估算，仅供参考，以官方教务为准。', theme),
                _buildBulletText('请合理使用，严禁高频批量抓取或实施任何影响学校教务系统正常运行的行为。', theme),
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
          Text('• ', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 11)),
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

  /// 文档切换 Tab（门禁模式展示已读状态绿色圆点）
  Widget _buildDocSelector(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: SegmentedButton<int>(
        segments: [
          for (int i = 0; i < _docs.length; i++)
            ButtonSegment<int>(
              value: i,
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_docs[i].title),
                  if (widget.isGate) ...[
                    const SizedBox(width: 4),
                    Icon(
                      _docsRead[i] ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                      size: 13,
                      color: _docsRead[i] ? Colors.green : theme.colorScheme.outline.withValues(alpha: 0.6),
                    ),
                  ],
                ],
              ),
            ),
        ],
        selected: {_selectedDoc},
        onSelectionChanged: (val) => _switchDoc(val.first),
      ),
    );
  }

  /// 预处理 Markdown 源码中中文标点与加粗语法冲突的边界情况
  /// 将形如 **“文字”** 或 **"文字"** 自动转换为 “**文字**”，避免 CommonMark 将 ** 识别为纯字符
  static String _sanitizeMarkdown(String raw) {
    // 1. 处理紧随括号说明的情况：**“文字”（注记）** -> “**文字**”（注记）
    var text = raw.replaceAllMapped(
      RegExp(r'\*\*([“"「『])(.*?)([”"」』])([（\(].*?[）\)])\*\*'),
      (m) => '${m[1]}**${m[2]}**${m[3]}${m[4]}',
    );
    // 2. 处理标准成对引号：**“文字”** -> “**文字**”
    text = text.replaceAllMapped(
      RegExp(r'\*\*([“"「『])(.*?)([”"」』])\*\*'),
      (m) => '${m[1]}**${m[2]}**${m[3]}',
    );
    // 3. 处理中文字符紧贴 **“ 的情况：字**“ -> 字 “**
    text = text.replaceAllMapped(
      RegExp(r'([\u4e00-\u9fa5])\*\*([“"「『])'),
      (m) => '${m[1]} ${m[2]}**',
    );
    return text;
  }

  /// 本地 Markdown 格式化排版多文档独立滚动阅读器
  Widget _buildDocReader(ThemeData theme) {
    final isWindows = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    final fallbackFonts = isWindows
        ? const ['Microsoft YaHei', 'Segoe UI', 'sans-serif']
        : const ['PingFang SC', 'sans-serif'];

    final markdownStyle = MarkdownStyleSheet.fromTheme(theme).copyWith(
      h1: theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.bold,
        color: theme.colorScheme.onSurface,
        fontSize: 18,
        fontFamilyFallback: fallbackFonts,
      ),
      h2: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: theme.colorScheme.primary,
        fontSize: 15,
        fontFamilyFallback: fallbackFonts,
      ),
      h3: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.onSurface,
        fontSize: 13.5,
        fontFamilyFallback: fallbackFonts,
      ),
      p: theme.textTheme.bodyMedium?.copyWith(
        fontSize: 13,
        height: 1.6,
        color: theme.colorScheme.onSurface,
        fontFamilyFallback: fallbackFonts,
      ),
      strong: TextStyle(
        fontWeight: FontWeight.bold,
        color: theme.colorScheme.onSurface,
        fontFamilyFallback: fallbackFonts,
      ),
      blockquote: theme.textTheme.bodySmall?.copyWith(
        fontSize: 12.5,
        height: 1.5,
        color: theme.colorScheme.onSurfaceVariant,
        fontStyle: FontStyle.normal,
        fontFamilyFallback: fallbackFonts,
      ),
      blockquotePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      blockquoteDecoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(6),
        border: Border(
          left: BorderSide(
            color: theme.colorScheme.primary,
            width: 3.5,
          ),
        ),
      ),
      tableBorder: TableBorder.all(
        color: theme.colorScheme.outlineVariant.withValues(alpha: 0.8),
        width: 0.8,
        borderRadius: BorderRadius.circular(4),
      ),
      tableHead: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 12,
        color: theme.colorScheme.onSurface,
        fontFamilyFallback: fallbackFonts,
      ),
      tableBody: TextStyle(
        fontSize: 12,
        height: 1.4,
        color: theme.colorScheme.onSurface,
        fontFamilyFallback: fallbackFonts,
      ),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
      listBullet: TextStyle(
        color: theme.colorScheme.primary,
        fontSize: 13,
      ),
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: IndexedStack(
        index: _selectedDoc,
        children: [
          for (int i = 0; i < _docs.length; i++)
            _buildSingleDocReader(i, theme, markdownStyle),
        ],
      ),
    );
  }

  /// 单个文档的独立渲染器，具备独立的 ScrollController，各 Tab 翻动互不干扰
  Widget _buildSingleDocReader(int index, ThemeData theme, MarkdownStyleSheet markdownStyle) {
    final rawText = _docTexts[index] ?? '加载中...';
    final sanitizedText = _sanitizeMarkdown(rawText);
    final controller = _scrollControllers[index];

    return Scrollbar(
      controller: controller,
      thumbVisibility: true,
      child: SingleChildScrollView(
        key: PageStorageKey<String>('legal_doc_scroll_$index'),
        controller: controller,
        padding: const EdgeInsets.only(right: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SelectionArea(
              child: MarkdownBody(
                data: sanitizedText,
                selectable: false, // SelectionArea handles selection
                styleSheet: markdownStyle,
              ),
            ),
            if (widget.isGate) ...[
              const SizedBox(height: 24),
              _buildDocBottomReaderCard(index, theme),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }

  /// 文档底部滑动阅读状态卡片与快捷下一份跳转
  Widget _buildDocBottomReaderCard(int index, ThemeData theme) {
    final isRead = _docsRead[index];
    final nextUnread = _docsRead.indexWhere((r) => !r);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isRead
            ? Colors.green.withValues(alpha: 0.08)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isRead
              ? Colors.green.withValues(alpha: 0.35)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isRead ? Icons.check_circle_rounded : Icons.arrow_downward_rounded,
                size: 18,
                color: isRead ? Colors.green : theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                isRead
                    ? '已完整阅读《${_docs[index].title}》'
                    : '请继续向下滑动至文档最末尾以完成阅读',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isRead ? Colors.green : theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          if (isRead && nextUnread != -1 && nextUnread != index) ...[
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: () => _switchDoc(nextUnread),
              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
              label: Text('继续阅读下一份：《${_docs[nextUnread].title}》'),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 底部门禁同意栏（仅在 isGate 模式展示）
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
          // 阅读进度提示条
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
                      color: _allDocsRead ? Colors.green : theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 显式勾选框（全部文书滑动阅读完毕后方可勾选）
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
                        content: Text('请先完整滑动阅读全部 3 份条款至底部（还剩 $_unreadCount 份待阅读）'),
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
          // 两个并排按钮
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

  /// 查阅模式底栏：展示本地存证信息与联系渠道
  Widget _buildReaderFooter(ThemeData theme) {
    final dateStr = _acceptedAt != null
        ? '${_acceptedAt!.year}-${_acceptedAt!.month.toString().padLeft(2, '0')}-${_acceptedAt!.day.toString().padLeft(2, '0')} ${_acceptedAt!.hour.toString().padLeft(2, '0')}:${_acceptedAt!.minute.toString().padLeft(2, '0')}'
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
          Row(
            children: [
              Icon(Icons.verified_outlined, size: 15, color: Colors.green.shade700),
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
