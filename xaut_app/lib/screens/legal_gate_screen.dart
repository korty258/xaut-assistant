import 'dart:io' show Platform, exit;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  final List<({String title, String assetPath})> _docs = const [
    (title: '用户协议', assetPath: 'assets/legal/terms_of_service.md'),
    (title: '隐私政策', assetPath: 'assets/legal/privacy_policy.md'),
    (title: '免责声明', assetPath: 'assets/legal/disclaimer.md'),
  ];

  @override
  void initState() {
    super.initState();
    _selectedDoc = widget.initialDocIndex.clamp(0, _docs.length - 1);
    _initData();
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

  /// 文档切换 Tab
  Widget _buildDocSelector(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: SegmentedButton<int>(
        segments: [
          for (int i = 0; i < _docs.length; i++)
            ButtonSegment<int>(
              value: i,
              label: Text(_docs[i].title),
            ),
        ],
        selected: {_selectedDoc},
        onSelectionChanged: (val) {
          setState(() {
            _selectedDoc = val.first;
          });
        },
      ),
    );
  }

  /// 纯本地 Markdown 文本滚动阅读器
  Widget _buildDocReader(ThemeData theme) {
    final text = _docTexts[_selectedDoc] ?? '加载中...';

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
      child: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(right: 8),
          child: SelectableText(
            text,
            style: TextStyle(
              fontSize: 13,
              height: 1.6,
              color: theme.colorScheme.onSurface,
              fontFamilyFallback: const ['Microsoft YaHei', 'PingFang SC', 'sans-serif'],
            ),
          ),
        ),
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
          // 显式勾选框（默认未勾选）
          InkWell(
            onTap: () {
              setState(() {
                _agreed = !_agreed;
              });
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Checkbox(
                    value: _agreed,
                    onChanged: (val) {
                      setState(() {
                        _agreed = val ?? false;
                      });
                    },
                  ),
                  Expanded(
                    child: Text(
                      '我已阅读并同意《用户协议》《隐私政策》与《免责声明》，并充分理解其中的免责与责任限制条款。',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
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
                  onPressed: _agreed ? _onAgree : null,
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
