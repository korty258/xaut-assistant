import 'package:flutter/material.dart';
import '../screens/webview_login_screen.dart';
import '../services/storage_service.dart';

class DecryptionErrorView extends StatelessWidget {
  final String moduleName;
  final VoidCallback onReset;

  const DecryptionErrorView({
    super.key,
    required this.moduleName,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.lock_reset_rounded,
                size: 72,
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '本地$moduleName解密失败',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '由于主安全密钥变更或本地缓存数据损坏，无法解密既有$moduleName数据。\n'
              '您的教务隐私数据不会被上传泄露。可通过重新同步教务恢复，或重置损坏的本地密文。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const WebViewLoginScreen()),
                );
              },
              icon: const Icon(Icons.cloud_sync_rounded, size: 22),
              label: const Text(
                '登录强智教务重新同步',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('重置损坏的本地数据'),
                    content: const Text(
                      '确定要重置本地密文缓存吗？\n\n'
                      '重置后将清除损坏的加密缓存并安全重新生成本地主密钥，无需重新签署法律协议。',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('确定重置'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await StorageService.resetCorruptedData();
                  onReset();
                }
              },
              icon: const Icon(Icons.delete_sweep_rounded),
              label: const Text('重置并清空损坏数据'),
            ),
          ],
        ),
      ),
    );
  }
}
