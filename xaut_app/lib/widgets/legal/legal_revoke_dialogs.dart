import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../services/legal_service.dart';

/// 法律门禁退出、撤回同意与部分清理结果提示弹窗集合
abstract final class LegalRevokeDialogs {
  static Future<bool?> confirmDisagree(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.warning_amber_rounded,
          size: 36,
          color: Colors.orange,
        ),
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
  }

  static Future<bool?> confirmRevokeConsent(BuildContext context) {
    final isWindows = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.delete_forever_rounded,
          size: 36,
          color: Theme.of(ctx).colorScheme.error,
        ),
        title: const Text('撤回同意并清空数据？'),
        content: Text(
          '依据《个人信息保护法》第 15 条，您有权撤回同意。\n\n'
          '撤回同意后，本软件将清除保存在本机设备上的所有课表、成绩、考试数据以及授权凭证，并退回首次启动法律门禁。\n\n'
          '${isWindows ? "【Windows 提示】由于便携版及 WebView2 进程特性，彻底清除内嵌网页缓存请在退出软件后手动删除程序同级目录下的 *.WebView2 文件夹及 %APPDATA%\\Jinhua Assistant OpenSource Community\\金花助手 目录。\n\n" : ""}'
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
  }

  static Future<String?> showPartialCleanupDialog(
    BuildContext context, {
    required RevokeCleanupResult cleanupResult,
    required bool isWindows,
  }) {
    final items = cleanupResult.describeItems(isWindows: isWindows);
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.warning_amber_rounded,
          size: 36,
          color: Theme.of(ctx).colorScheme.error,
        ),
        title: const Text('部分本地数据未能完成清理'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('已执行撤回清理，各项真实处理结果如下：'),
              const SizedBox(height: 10),
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        item.isFailedUnqueued
                            ? Icons.error_outline_rounded
                            : (item.isQueued
                                ? Icons.schedule_rounded
                                : Icons.check_circle_outline_rounded),
                        size: 18,
                        color: item.isFailedUnqueued
                            ? Theme.of(ctx).colorScheme.error
                            : (item.isQueued ? Colors.orange : Colors.green),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${item.label}：${item.status}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                '说明：标记为“未加入待清理队列”的失败项不会在下次启动时自动补偿。'
                '您可以点击“重试清理”，或前往${isWindows ? '应用数据目录 (%APPDATA%\\Jinhua Assistant OpenSource Community\\金花助手) 与同级 *.WebView2 目录手动删除' : '系统应用设置中手动执行“清除全部数据”'}。',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('gate'),
            child: const Text('返回法律门禁'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('retry'),
            child: const Text('重试清理'),
          ),
        ],
      ),
    );
  }
}
