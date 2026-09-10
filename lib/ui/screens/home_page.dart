import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../../services/download/download_engine.dart';
import '../../services/download/douyin_bridge.dart';
import '../../services/download/xhs_bridge.dart';
import '../../services/log_service.dart';
import '../../services/storage/cookie_store.dart';

/// 全新主页 — 搜索栏主导 + 快捷按钮 + 实时日志
class HomePage extends StatefulWidget {
  final VoidCallback onOpenDrawer;
  const HomePage({super.key, required this.onOpenDrawer});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _urlCtrl = TextEditingController();
  final _log = LogService.instance;
  bool _busy = false;
  String _platform = 'douyin';
  bool _logVisible = false;

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
      _platform == 'xhs'
          ? await XhsBridge.setCookie(c)
          : await DouyinBridge.setCookie(c);
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

  void _onHotList() {
    _do('热榜', () async {
      await _syncCookie();
      return DouyinBridge.getHotList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return CustomScrollView(slivers: [
      // Top app bar with drawer button
      SliverAppBar(
        leading: IconButton(
            icon: const Icon(Icons.menu), onPressed: widget.onOpenDrawer),
        title: const Text('FNB Download'),
        floating: true,
        actions: [
          IconButton(
            icon: Badge(
                isLabelVisible: _log.length > 0,
                label:
                    Text('${_log.length}', style: const TextStyle(fontSize: 9)),
                child: const Icon(Icons.terminal)),
            onPressed: () => setState(() => _logVisible = !_logVisible),
          ),
          const SizedBox(width: 4),
        ],
      ),
      SliverToBoxAdapter(
          child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 平台选择
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                  value: 'douyin',
                  icon: Icon(Icons.video_library, size: 18),
                  label: Text('抖音')),
              ButtonSegment(
                  value: 'xhs',
                  icon: Icon(Icons.book, size: 18),
                  label: Text('小红书')),
            ],
            selected: {_platform},
            onSelectionChanged: (s) => setState(() => _platform = s.first),
          ),
          const SizedBox(height: 16),
          // 搜索栏
          SearchBar(
            controller: _urlCtrl,
            hintText: '粘贴${_platform == 'douyin' ? '抖音' : '小红书'}链接或搜索关键词',
            leading: const Padding(
                padding: EdgeInsets.only(left: 8), child: Icon(Icons.link)),
            trailing: [
              if (_urlCtrl.text.isNotEmpty)
                IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _urlCtrl.clear)),
              IconButton(
                  icon: const Icon(Icons.paste),
                  onPressed: () async {
                    final d = await Clipboard.getData(Clipboard.kTextPlain);
                    if (d?.text != null && d!.text!.isNotEmpty)
                      setState(() => _urlCtrl.text = d.text!);
                  }),
            ],
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _onDownload(),
          ),
          const SizedBox(height: 12),
          // 主操作按钮
          Row(children: [
            Expanded(
                child: FilledButton.icon(
              onPressed: _busy ? null : _onDownload,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download),
              label: Text(_busy ? '处理中...' : '下载'),
            )),
            const SizedBox(width: 12),
            Expanded(
                child: OutlinedButton.icon(
              onPressed: _busy ? null : _onParse,
              icon: const Icon(Icons.info_outline),
              label: const Text('解析'),
            )),
          ]),
          const SizedBox(height: 24),
          // 快捷功能区
          Text('更多功能',
              style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
        ]),
      )),
      // 功能网格
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverGrid.count(
          crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.8,
          children: [
            if (_platform == 'douyin')
              _gridBtn(context, Icons.local_fire_department, '热榜', cs.error,
                  cs.errorContainer, _busy ? null : _onHotList),
            _gridBtn(
                context,
                Icons.comment,
                '评论',
                cs.tertiary,
                cs.tertiaryContainer,
                _busy ? null : () => _simpleCall('scrape_comments', '评论')),
            _gridBtn(
                context,
                Icons.music_note,
                '音频',
                cs.secondary,
                cs.secondaryContainer,
                _busy ? null : () => _simpleCall('extract_audio', '音频')),
            _gridBtn(
                context,
                Icons.image,
                '封面',
                cs.primary,
                cs.primaryContainer,
                _busy ? null : () => _simpleCall('download_cover', '封面')),
          ],
        ),
      ),
      // 日志
      if (_logVisible)
        SliverToBoxAdapter(
            child: Padding(
          padding: const EdgeInsets.all(16),
          child: _buildLogPanel(context),
        )),
      const SliverToBoxAdapter(child: SizedBox(height: 32)),
    ]);
  }

  void _simpleCall(String fn, String label) {
    final url = _firstUrl;
    if (url.isEmpty) {
      _toast('请输入链接', err: true);
      return;
    }
    _do(label, () async {
      await _syncCookie();
      return DownloadEngine.instance.callInBackground(fn, {
        'platform': _platform,
        'link': url,
        'save_path': await _outDir(),
        'task_id': DownloadEngine.instance.newTaskId(),
      });
    });
  }

  Widget _gridBtn(BuildContext ctx, IconData icon, String label, Color fg,
      Color bg, VoidCallback? onTap) {
    return Card(
      color: bg.withValues(alpha: 0.3),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
          onTap: onTap,
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: fg, size: 28),
              const SizedBox(height: 6),
              Text(label,
                  style:
                      Theme.of(ctx).textTheme.labelLarge?.copyWith(color: fg))
            ]),
          )),
    );
  }

  Widget _buildLogPanel(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final entries = _log.entries.reversed.take(15).toList();
    return ValueListenableBuilder<int>(
      valueListenable: _log.notifier,
      builder: (_, __, ___) => Card(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
              child: Row(children: [
                Icon(Icons.terminal, size: 16, color: cs.primary),
                const SizedBox(width: 8),
                const Text('日志',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _logVisible = false)),
              ])),
          if (entries.isEmpty)
            const Padding(
                padding: EdgeInsets.all(16),
                child:
                    Center(child: Text('无日志', style: TextStyle(fontSize: 12))))
          else
            ...entries.map((e) => Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  child: Text(
                      '${e.timestamp.hour.toString().padLeft(2, '0')}:${e.timestamp.minute.toString().padLeft(2, '0')}:${e.timestamp.second.toString().padLeft(2, '0')}  ${e.message}',
                      style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                          fontFamily: 'monospace')),
                )),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}
