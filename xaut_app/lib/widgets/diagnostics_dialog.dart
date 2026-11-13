import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/legal_gate_screen.dart';
import '../services/diagnostics_service.dart';

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
      show(context);
      return true;
    }
    if (value == menuActionAboutLegal) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LegalGateScreen(isGate: false)),
      );
      return true;
    }
    return false;
  }

  /// 复制开源仓库问题反馈地址并弹出提示
  static void copyIssuesUrl(BuildContext context) {
    Clipboard.setData(const ClipboardData(text: issuesUrl));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('开源仓库问题反馈地址已复制: $issuesUrl'),
        duration: Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 弹出完全脱敏的客户端运行与同步诊断摘要
  static Future<void> show(BuildContext context) async {
    final report = await DiagnosticsService.buildDiagnosticReport();
    if (!context.mounted) return;
    final theme = Theme.of(context);

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.monitor_heart_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            const Text('客户端脱敏诊断摘要', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.security_rounded, size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '以下诊断摘要仅含应用版本与同步状态码，不含学号、密码、Cookie、课表或成绩等任何个人数据。',
                          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: SelectableText(
                    report,
                    style: TextStyle(
                      fontFamily: defaultTargetPlatform == TargetPlatform.windows ? 'Consolas' : 'monospace',
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
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
              Clipboard.setData(ClipboardData(text: report));
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
    );
  }
}
