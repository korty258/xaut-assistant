import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import '../../services/legal_service.dart';

typedef LegalDocItem = ({String title, String assetPath});

/// 打开应用标准开源组件许可证页（复用自顶栏与「开源致谢」页尾按钮）
void showJinhuaLicensePage(BuildContext context) {
  showLicensePage(
    context: context,
    applicationName: '金花助手',
    applicationVersion: LegalService.appVersion,
    applicationIcon: Padding(
      padding: const EdgeInsets.all(8.0),
      child: Image.asset('assets/logo.png', width: 44, height: 44),
    ),
    applicationLegalese: 'Copyright (C) 2026 Jinhua Assistant Contributors\n'
        '基于 GNU General Public License v3.0 (GPL-3.0) 授权',
  );
}

/// 法务文书顶部标签切换控件
class LegalDocSelector extends StatelessWidget {
  final List<LegalDocItem> docs;
  final List<bool> docsRead;
  final int selectedDoc;
  final bool isGate;
  final ValueChanged<int> onSelect;

  const LegalDocSelector({
    super.key,
    required this.docs,
    required this.docsRead,
    required this.selectedDoc,
    required this.isGate,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SegmentedButton<int>(
          segments: [
            for (int i = 0; i < docs.length; i++)
              ButtonSegment<int>(
                value: i,
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        docs[i].title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isGate) ...[
                      const SizedBox(width: 4),
                      Icon(
                        docsRead[i]
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked,
                        size: 13,
                        color: docsRead[i]
                            ? Colors.green
                            : theme.colorScheme.outline.withValues(alpha: 0.6),
                      ),
                    ],
                  ],
                ),
              ),
          ],
          selected: {selectedDoc},
          onSelectionChanged: (val) => onSelect(val.first),
        ),
      ),
    );
  }
}

/// 本地 Markdown 法律文书独立滚动阅读器（含中文引号加粗预处理与全量开源组件页入口）
class LegalMarkdownReader extends StatelessWidget {
  final List<LegalDocItem> docs;
  final List<bool> docsRead;
  final List<ScrollController> scrollControllers;
  final Map<int, String> docTexts;
  final int selectedDoc;
  final bool isGate;
  final ValueChanged<int> onSwitchDoc;

  const LegalMarkdownReader({
    super.key,
    required this.docs,
    required this.docsRead,
    required this.scrollControllers,
    required this.docTexts,
    required this.selectedDoc,
    required this.isGate,
    required this.onSwitchDoc,
  });

  /// 预处理 Markdown 源码中中文标点与加粗语法冲突的边界情况
  static String sanitizeMarkdown(String raw) {
    var text = raw.replaceAllMapped(
      RegExp(r'\*\*([“"「『])(.*?)([”"」』])([（\(].*?[）\)])\*\*'),
      (m) => '${m[1]}**${m[2]}**${m[3]}${m[4]}',
    );
    text = text.replaceAllMapped(
      RegExp(r'\*\*([“"「『])(.*?)([”"」』])\*\*'),
      (m) => '${m[1]}**${m[2]}**${m[3]}',
    );
    text = text.replaceAllMapped(
      RegExp(r'([\u4e00-\u9fa5])\*\*([“"「『])'),
      (m) => '${m[1]} ${m[2]}**',
    );
    return text;
  }

  static MarkdownStyleSheet _buildStyleSheet(ThemeData theme) {
    final isWindows = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    final fallbackFonts = isWindows
        ? const ['Microsoft YaHei', 'Segoe UI', 'sans-serif']
        : const ['PingFang SC', 'sans-serif'];

    return MarkdownStyleSheet.fromTheme(theme).copyWith(
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
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final markdownStyle = _buildStyleSheet(theme);

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
        index: selectedDoc,
        children: [
          for (int i = 0; i < docs.length; i++)
            _buildSingleDocReader(context, i, theme, markdownStyle),
        ],
      ),
    );
  }

  Widget _buildSingleDocReader(
    BuildContext context,
    int index,
    ThemeData theme,
    MarkdownStyleSheet markdownStyle,
  ) {
    final rawText = docTexts[index] ?? '加载中...';
    final sanitizedText = sanitizeMarkdown(rawText);
    final controller = scrollControllers[index];

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
                selectable: false,
                styleSheet: markdownStyle,
              ),
            ),
            if (isGate) ...[
              const SizedBox(height: 24),
              _buildDocBottomReaderCard(index, theme),
              const SizedBox(height: 16),
            ] else if (index == 3) ...[
              const SizedBox(height: 24),
              Center(
                child: FilledButton.tonalIcon(
                  onPressed: () => showJinhuaLicensePage(context),
                  icon: const Icon(Icons.policy_outlined),
                  label: const Text('打开全量开源组件许可证页面 (LicensePage)'),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDocBottomReaderCard(int index, ThemeData theme) {
    final isRead = docsRead[index];
    final nextUnread = docsRead.indexWhere((r) => !r);

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
              Flexible(
                child: Text(
                  isRead
                      ? '已完整阅读《${docs[index].title}》'
                      : '请继续向下滑动至文档最末尾以完成阅读',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isRead ? Colors.green : theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          if (isRead && nextUnread != -1 && nextUnread != index) ...[
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: () => onSwitchDoc(nextUnread),
              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
              label: Text('继续阅读下一份：《${docs[nextUnread].title}》'),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
