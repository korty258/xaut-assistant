import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/legal_gate_screen.dart';
import '../services/diagnostics_service.dart';
import '../services/parser_service.dart';
import '../services/storage_service.dart';

/// 客户端脱敏诊断摘要弹窗与支持菜单共享入口
class DiagnosticsDialog {
  DiagnosticsDialog._();

  static const String issuesUrl = 'https://github.com/korty258/xaut-assistant/issues';
  static const String menuActionDiagnostics = 'diagnostics';
  static const String menuActionAboutLegal = 'about_legal';

  /// 供各主页面「更多操作」菜单复用的支持与合规菜单项
  static List<PopupMenuEntry<String>> buildSupportMenuEntries() => const [
        PopupMenuDivider(),
        PopupMenuItem(
          value: menuActionDiagnostics,
          child: Row(
            children: [
              Icon(Icons.bug_report_outlined, size: 18),
              SizedBox(width: 8),
              Text('查看诊断摘要'),
            ],
          ),
        ),
        PopupMenuItem(
          value: menuActionAboutLegal,
          child: Row(
            children: [
              Icon(Icons.policy_outlined, size: 18),
              SizedBox(width: 8),
              Text('关于与法律条款'),
            ],
          ),
        ),
      ];

  /// 统一处理各主页面「更多操作」中的支持与合规菜单动作
  static bool handleSupportMenuSelection(BuildContext context, String value) {
    if (value == menuActionDiagnostics) {
      unawaited(show(context));
      return true;
    }
    if (value == menuActionAboutLegal) {
      unawaited(
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LegalGateScreen(isGate: false)),
        ),
      );
      return true;
    }
    return false;
  }

  /// 复制开源仓库问题反馈地址并弹出提示
  static void copyIssuesUrl(BuildContext context) {
    unawaited(Clipboard.setData(const ClipboardData(text: issuesUrl)));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('开源仓库问题反馈地址已复制: $issuesUrl'),
        duration: Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 弹出完全脱敏的客户端运行与同步诊断摘要（原生结构化展示 + 一键复制 Markdown 反馈报告）
  static Future<void> show(BuildContext context) async {
    var snapshot = await DiagnosticsService.collectSnapshot();
    var report = snapshot.toMarkdownReport();
    if (!context.mounted) return;
    final theme = Theme.of(context);
    bool isRetryingMigration = false;
    String? migrationFeedback;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.monitor_heart_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '客户端脱敏诊断摘要',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildPrivacyBanner(theme),
                  const SizedBox(height: 12),
                  _buildSectionCard(
                    theme,
                    icon: Icons.devices_outlined,
                    title: '运行环境',
                    children: [
                      _buildInfoRow(theme, '应用版本', snapshot.appVersion, monospace: true),
                      _buildInfoRow(theme, '合规条款版本', snapshot.legalVersion, monospace: true),
                      _buildInfoRow(theme, '运行平台', snapshot.platform),
                      _buildInfoRow(theme, 'WebView2 运行时', snapshot.webView2Info),
                      _buildInfoRow(
                        theme,
                        '密文升级状态',
                        snapshot.pendingMigrationCount == 0
                            ? '已完成或无需升级'
                            : '待重试 ${snapshot.pendingMigrationCount} 项'
                                '${snapshot.hasKeyBlockedMigration ? " (密钥受阻)" : ""}',
                      ),
                      if (snapshot.pendingMigrationCount > 0 ||
                          migrationFeedback != null) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (snapshot.pendingMigrationCount > 0)
                              OutlinedButton.icon(
                                onPressed: isRetryingMigration
                                    ? null
                                    : () async {
                                        setDialogState(() {
                                          isRetryingMigration = true;
                                          migrationFeedback = null;
                                        });
                                        final res = await StorageService
                                            .retryPendingCryptoMigrations();
                                        final nextSnapshot =
                                            await DiagnosticsService.collectSnapshot();
                                        if (!ctx.mounted) return;
                                        setDialogState(() {
                                          isRetryingMigration = false;
                                          snapshot = nextSnapshot;
                                          report = nextSnapshot.toMarkdownReport();
                                          if (res.failed == 0) {
                                            migrationFeedback = res.succeeded > 0
                                                ? '已成功完成 ${res.succeeded} 项密文升级'
                                                : '暂无待升级项';
                                          } else {
                                            migrationFeedback = res.hadKeyError
                                                ? '仍有 ${res.failed} 项受密钥访问异常阻塞'
                                                : '仍有 ${res.failed} 项写入失败，请稍后重试';
                                          }
                                        });
                                      },
                                icon: const Icon(Icons.security_update_good_outlined,
                                    size: 16),
                                label: Text(
                                  isRetryingMigration ? '正在重试升级...' : '重试密文升级',
                                ),
                              ),
                            if (migrationFeedback != null)
                              Text(
                                migrationFeedback!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: snapshot.pendingMigrationCount == 0
                                      ? Colors.green
                                      : Colors.orange,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                const SizedBox(height: 10),
                _buildSectionCard(
                  theme,
                  icon: Icons.schedule_rounded,
                  title: '模块本地同步时间',
                  children: [
                    _buildInfoRow(
                      theme,
                      '课表模块',
                      DiagnosticsService.formatDateTime(snapshot.coursesSyncTime),
                      monospace: true,
                    ),
                    _buildInfoRow(
                      theme,
                      '成绩模块',
                      DiagnosticsService.formatDateTime(snapshot.gradesSyncTime),
                      monospace: true,
                    ),
                    _buildInfoRow(
                      theme,
                      '考试模块',
                      DiagnosticsService.formatDateTime(snapshot.examsSyncTime),
                      monospace: true,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildSectionCard(
                  theme,
                  icon: Icons.sync_alt_rounded,
                  title: '最近一次教务同步遥测',
                  children: snapshot.lastSyncTimestamp == null
                      ? [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              '本次启动后尚未执行任何同步操作',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ]
                      : [
                          _buildInfoRow(
                            theme,
                            '触发时间',
                            DiagnosticsService.formatDateTime(snapshot.lastSyncTimestamp),
                            monospace: true,
                          ),
                          _buildInfoRow(theme, '触发模式', snapshot.triggerMode ?? '未知'),
                          _buildInfoRow(
                            theme,
                            '总耗时',
                            '${snapshot.durationMs ?? 0} ms',
                            monospace: true,
                          ),
                          const Divider(height: 14),
                          _buildModuleTelemetryRow(
                            theme,
                            '课表模块',
                            snapshot.coursesStatus,
                            snapshot.coursesErrorCategory,
                          ),
                          _buildModuleTelemetryRow(
                            theme,
                            '成绩模块',
                            snapshot.gradesStatus,
                            snapshot.gradesErrorCategory,
                          ),
                          _buildModuleTelemetryRow(
                            theme,
                            '考试模块',
                            snapshot.examsStatus,
                            snapshot.examsErrorCategory,
                          ),
                        ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
          FilledButton.icon(
            onPressed: () {
              unawaited(Clipboard.setData(ClipboardData(text: report)));
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('脱敏诊断摘要已成功复制到剪贴板'),
                  duration: Duration(seconds: 3),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('复制到剪贴板'),
          ),
          ],
        ),
      ),
    );
  }

  static Widget _buildPrivacyBanner(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.security_rounded, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '以下诊断摘要仅含应用版本与同步状态码，不含学号、密码、Cookie、课表或成绩等任何个人数据。',
              style: TextStyle(fontSize: 12, height: 1.4, color: theme.colorScheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildSectionCard(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  static Widget _buildInfoRow(
    ThemeData theme,
    String label,
    String value, {
    bool monospace = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                fontFamily: monospace ? 'monospace' : null,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildModuleTelemetryRow(
    ThemeData theme,
    String moduleName,
    SyncModuleStatus? status,
    String errorCategory,
  ) {
    final badge = _resolveStatusBadge(theme, status);
    final hasError = errorCategory.isNotEmpty && errorCategory != 'none';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(
            moduleName,
            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
          ),
          const Spacer(),
          if (hasError) ...[
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                errorCategory,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: badge.bg,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              badge.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: badge.fg,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static ({String label, Color bg, Color fg}) _resolveStatusBadge(
    ThemeData theme,
    SyncModuleStatus? status,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    switch (status) {
      case SyncModuleStatus.ok:
        return (
          label: '正常 (ok)',
          bg: isDark ? Colors.green.withValues(alpha: 0.22) : Colors.green.shade50,
          fg: isDark ? Colors.green.shade300 : Colors.green.shade800,
        );
      case SyncModuleStatus.empty:
        return (
          label: '无数据 (empty)',
          bg: isDark ? Colors.orange.withValues(alpha: 0.22) : Colors.orange.shade50,
          fg: isDark ? Colors.orange.shade300 : Colors.orange.shade800,
        );
      case SyncModuleStatus.notLoggedIn:
        return (
          label: '未登录',
          bg: theme.colorScheme.surfaceContainerHighest,
          fg: theme.colorScheme.onSurfaceVariant,
        );
      case SyncModuleStatus.error:
        return (
          label: '异常 (error)',
          bg: theme.colorScheme.errorContainer,
          fg: theme.colorScheme.onErrorContainer,
        );
      case null:
        return (
          label: '未触发',
          bg: theme.colorScheme.surfaceContainerHighest,
          fg: theme.colorScheme.onSurfaceVariant,
        );
    }
  }
}
