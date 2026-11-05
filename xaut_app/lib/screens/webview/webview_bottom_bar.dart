import 'package:flutter/material.dart';
import 'webview_constants.dart';

/// 底部常驻同步操作按钮栏 (支持阶段进度提示)
class WebViewBottomBar extends StatelessWidget {
  final String currentUrl;
  final bool isLoading;
  final String? statusMessage;
  final VoidCallback onSyncAll;
  final VoidCallback onSyncCurrentPage;

  const WebViewBottomBar({
    super.key,
    required this.currentUrl,
    required this.isLoading,
    this.statusMessage,
    required this.onSyncAll,
    required this.onSyncCurrentPage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeNav = NavDestination.fromUrl(currentUrl);
    final pageSyncInfo = activeNav.syncInfo;

    return SafeArea(
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 异步阶段进度提示条
            if (isLoading && statusMessage != null && statusMessage!.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(strokeWidth: 2.0),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        statusMessage!,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            Row(
              children: [
                // 1. 默认主选项：一键同步全部 (课表/成绩/考试 一次搞定)
                Expanded(
                  flex: 6,
                  child: FilledButton.icon(
                    onPressed: isLoading ? null : onSyncAll,
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
                    onPressed: isLoading ? null : onSyncCurrentPage,
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
          ],
        ),
      ),
    );
  }
}
