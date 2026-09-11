import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../../services/download/download_engine.dart';
import '../../services/log_service.dart';
import '../../services/storage/cookie_store.dart';

/// 首页 — 链接输入 + 平台切换 + 核心操作 + 实时日志
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

/// 功能入口定义
class _FeatureEntry {
  final String engineFn;
  final String label;
  final IconData icon;
  const _FeatureEntry(this.engineFn, this.label, this.icon);
}

/// 抖音专属功能
const _douyinFeatures = [
  _FeatureEntry('get_hot_list', '热榜', Icons.whatshot_rounded),
  _FeatureEntry('search_general', '搜索', Icons.search_rounded),
  _FeatureEntry('batch_download_account', '批量下载作者', Icons.group_add_rounded),
  _FeatureEntry('batch_download_mix', '批量下载合集', Icons.collections_bookmark_rounded),
  _FeatureEntry('scrape_comments', '评论采集', Icons.comment_rounded),
];

/// 小红书专属功能
const _xhsFeatures = [
  _FeatureEntry('extract_data', '提取数据', Icons.analytics_rounded),
  _FeatureEntry('batch_download_account', '批量下载用户', Icons.group_add_rounded),
  _FeatureEntry('batch_download_mix', '批量下载合集', Icons.collections_bookmark_rounded),
  _FeatureEntry('scrape_comments', '评论采集', Icons.comment_rounded),
];

class _HomePageState extends State<HomePage> {
  final _urlCtrl = TextEditingController();
  final _log = LogService.instance;
  bool _busy = false;
  String _platform = 'douyin';
  bool _logExpanded = false;

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  String get _firstUrl {
    final m = RegExp(r'https?://\S+').firstMatch(_urlCtrl.text.trim());
    return m?.group(0) ?? _urlCtrl.text.trim();
  }

  Future<void> _syncCookie() async {
    final s = CookieStore(platform: _platform);
    await s.load();
    final c = s.getActiveCookie();
    if (c != null && c.isNotEmpty) {
      await DownloadEngine.instance
          .call('set_cookie', {'platform': _platform, 'cookie': c});
    }
  }

  void _toast(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      backgroundColor: err ? Theme.of(context).colorScheme.error : null,
    ));
  }

  Future<void> _do(
      String label, Future<Map<String, dynamic>> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    _log.info('$label...', tag: _platform);
    try {
      final r = await action();
      final ok = r['success'] == true;
      _log.info(ok ? '${r['message'] ?? '完成'}' : '失败: ${r['message']}',
          tag: _platform);
      _toast(ok ? '${r['message'] ?? '完成'}' : '失败: ${r['message']}', err: !ok);
    } catch (e) {
      _log.error('$label 异常: $e', tag: _platform);
      _toast('异常: $e', err: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<String> _outDir() async {
    final d = await getApplicationDocumentsDirectory();
    final p = '${d.path}/${_platform == 'xhs' ? 'XhsDownload' : 'DyDownload'}';
    await Directory(p).create(recursive: true);
    return p;
  }

  void _onDownload() {
    final url = _firstUrl;
    if (url.isEmpty) {
      _toast('请输入链接', err: true);
      return;
    }
    _do('下载', () async {
      await _syncCookie();
      return DownloadEngine.instance.call('parse_and_download', {
        'platform': _platform,
        'link': url,
        'save_path': await _outDir(),
        'task_id': DownloadEngine.instance.newTaskId(),
      });
    });
  }

  void _onParse() {
    final url = _firstUrl;
    if (url.isEmpty) {
      _toast('请输入链接', err: true);
      return;
    }
    _do('解析', () async {
      await _syncCookie();
      return DownloadEngine.instance
          .call('detect_link_info', {'platform': _platform, 'link': url});
    });
  }



  // ──────────────────── UI ────────────────────

  List<_FeatureEntry> get _features =>
      _platform == 'douyin' ? _douyinFeatures : _xhsFeatures;

  void _onFeatureTap(String engineFn) {
    final url = _firstUrl;
    if (url.isEmpty) {
      _toast('请先输入链接', err: true);
      return;
    }
    _do(engineFn, () async {
      await _syncCookie();
      return DownloadEngine.instance.callInBackground(engineFn, {
        'platform': _platform,
        'link': url,
        'save_path': await _outDir(),
        'task_id': DownloadEngine.instance.newTaskId(),
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        // ── AppBar（不用 large，避免折叠截断） ──
        SliverAppBar(
          floating: true,
          title: const Text('FNB Download'),
          actions: [
            Badge(
              isLabelVisible: _log.entries.isNotEmpty,
              label: Text('${_log.entries.length}',
                  style: const TextStyle(fontSize: 9)),
              child: IconButton(
                icon: Icon(
                  _logExpanded ? Icons.terminal : Icons.terminal_outlined,
                  size: 22,
                ),
                onPressed: () => setState(() => _logExpanded = !_logExpanded),
                tooltip: '日志',
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),

        // ── 主体内容 ──
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          sliver: SliverList.list(
            children: [
              // 平台选择器
              _PlatformSelector(
                platform: _platform,
                onChanged: (p) => setState(() => _platform = p),
              ),
              const SizedBox(height: 16),

              // URL 输入区
              _UrlInputCard(
                controller: _urlCtrl,
                platform: _platform,
                busy: _busy,
                onChanged: () => setState(() {}),
                onPaste: () async {
                  final d = await Clipboard.getData(Clipboard.kTextPlain);
                  if (d?.text != null && d!.text!.isNotEmpty) {
                    setState(() => _urlCtrl.text = d.text!);
                  }
                },
                onClear: () => setState(() => _urlCtrl.clear()),
                onSubmitted: _onDownload,
              ),
              const SizedBox(height: 16),

              // 操作按钮
              _ActionButtons(
                busy: _busy,
                onDownload: _onDownload,
                onParse: _onParse,
              ),

              const SizedBox(height: 20),

              // ── 功能入口（按平台动态切换） ──
              Text(
                _platform == 'douyin' ? '抖音工具' : '小红书工具',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _features.map((f) {
                  return ActionChip(
                    avatar: Icon(f.icon, size: 18),
                    label: Text(f.label),
                    onPressed: _busy ? null : () => _onFeatureTap(f.engineFn),
                  );
                }).toList(),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),

        // ── 日志面板 ──
        if (_logExpanded)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            sliver: SliverToBoxAdapter(child: _LogPanel(log: _log)),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  子组件
// ═══════════════════════════════════════════════════════════════

/// 平台选择器 — 圆角卡片 + 带图标的选项
class _PlatformSelector extends StatelessWidget {
  final String platform;
  final ValueChanged<String> onChanged;

  const _PlatformSelector({
    required this.platform,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _platformOption(
            context,
            icon: Icons.play_circle_fill_rounded,
            label: '抖音',
            value: 'douyin',
            color: cs.primary,
            selected: platform == 'douyin',
            onTap: () => onChanged('douyin'),
          ),
          _platformOption(
            context,
            icon: Icons.auto_stories_rounded,
            label: '小红书',
            value: 'xhs',
            color: cs.error,
            selected: platform == 'xhs',
            onTap: () => onChanged('xhs'),
          ),
        ],
      ),
    );
  }

  Widget _platformOption(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? color : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: selected ? color : cs.onSurfaceVariant,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.normal,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// URL 输入卡片
class _UrlInputCard extends StatelessWidget {
  final TextEditingController controller;
  final String platform;
  final bool busy;
  final VoidCallback onChanged;
  final VoidCallback onPaste;
  final VoidCallback onClear;
  final VoidCallback onSubmitted;

  const _UrlInputCard({
    required this.controller,
    required this.platform,
    required this.busy,
    required this.onChanged,
    required this.onPaste,
    required this.onClear,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Icon(Icons.link_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  '粘贴链接',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ],
            ),
          ),
          TextField(
            controller: controller,
            enabled: !busy,
            onChanged: (_) => onChanged(),
            onSubmitted: (_) => onSubmitted(),
            maxLines: 2,
            minLines: 1,
            decoration: InputDecoration(
              hintText:
                  '粘贴${platform == 'douyin' ? '抖音' : '小红书'}作品链接...',
              hintStyle: TextStyle(color: cs.outline),
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (controller.text.isNotEmpty)
                    IconButton(
                      icon: Icon(Icons.close_rounded,
                          size: 18, color: cs.outline),
                      onPressed: onClear,
                      visualDensity: VisualDensity.compact,
                    ),
                  IconButton(
                    icon: Icon(Icons.content_paste_rounded,
                        size: 18, color: cs.primary),
                    onPressed: onPaste,
                    tooltip: '粘贴',
                    visualDensity: VisualDensity.compact,
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

/// 主操作按钮（下载 + 解析）
class _ActionButtons extends StatelessWidget {
  final bool busy;
  final VoidCallback onDownload;
  final VoidCallback onParse;

  const _ActionButtons({
    required this.busy,
    required this.onDownload,
    required this.onParse,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: busy ? null : onDownload,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 52),
              textStyle: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600),
            ),
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.download_rounded, size: 20),
            label: Text(busy ? '处理中...' : '开始下载'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: busy ? null : onParse,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 52),
              textStyle: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w500),
            ),
            icon: const Icon(Icons.info_outline_rounded, size: 20),
            label: const Text('解析链接'),
          ),
        ),
      ],
    );
  }
}

/// 日志面板
class _LogPanel extends StatelessWidget {
  final LogService log;
  const _LogPanel({required this.log});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<int>(
      valueListenable: log.notifier,
      builder: (_, __, ___) {
        final entries = log.entries.reversed.take(20).toList();
        return Card(
          elevation: 0,
          color: cs.surfaceContainerLow,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: Row(
                  children: [
                    Icon(Icons.terminal_rounded, size: 18, color: cs.primary),
                    const SizedBox(width: 8),
                    Text(
                      '操作日志',
                      style:
                          Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.delete_sweep_rounded,
                          size: 18, color: cs.outline),
                      onPressed: log.clear,
                      visualDensity: VisualDensity.compact,
                      tooltip: '清除',
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text('暂无操作记录',
                        style: TextStyle(color: Colors.grey)),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    itemCount: entries.length,
                    itemBuilder: (ctx, i) {
                      final e = entries[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${e.timestamp.hour.toString().padLeft(2, '0')}:${e.timestamp.minute.toString().padLeft(2, '0')}:${e.timestamp.second.toString().padLeft(2, '0')}',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: cs.outline,
                                    fontFamily: 'monospace',
                                  ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                e.message,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
