import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../../services/download/download_engine.dart';
import '../../services/download/douyin_bridge.dart';
import '../../services/download/xhs_bridge.dart';
import '../../services/log_service.dart';
import '../../services/storage/cookie_store.dart';

class DownloadScreen extends StatefulWidget {
  const DownloadScreen({super.key});
  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen> {
  final _link = TextEditingController();
  bool _busy = false;
  String _platform = 'douyin';
  bool _showLog = false;
  final _log = LogService.instance;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  String get _firstLink {
    final m = RegExp(r'https?://\S+').firstMatch(_link.text.trim());
    return m?.group(0) ?? _link.text.trim();
  }

  Future<void> _syncCookie() async {
    final store = CookieStore(platform: _platform);
    await store.load();
    final cookie = store.getActiveCookie();
    if (cookie == null || cookie.isEmpty) return;
    if (_platform == 'xhs') {
      await XhsBridge.setCookie(cookie);
    } else {
      await DouyinBridge.setCookie(cookie);
    }
  }

  Future<String> _savePath() async {
    final dir = await getApplicationDocumentsDirectory();
    final p = _platform == 'xhs' ? 'XhsDownload' : 'DyDownload';
    final path = '${dir.path}/$p';
    await Directory(path).create(recursive: true);
    return path;
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ));
  }

  Future<void> _run(String label, Future<void> Function() task) async {
    if (_busy) return;
    setState(() => _busy = true);
    _log.info('$label...', tag: _platform);
    try {
      await task();
    } catch (e) {
      _log.error('$label 失败: $e', tag: _platform);
      _snack('执行失败: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _download() {
    final url = _firstLink;
    if (url.isEmpty) return _snack('请先输入链接', error: true);
    _run('下载', () async {
      await _syncCookie();
      final sp = await _savePath();
      final taskId = DownloadEngine.instance.newTaskId();
      final r = await DownloadEngine.instance.callInBackground(
          'parse_and_download', {
        'platform': _platform,
        'link': url,
        'save_path': sp,
        'task_id': taskId
      });
      final ok = r['success'] == true;
      _log.info(ok ? '${r['message'] ?? '下载完成'}' : '失败: ${r['message']}',
          tag: _platform);
      _snack(ok ? '${r['message'] ?? '下载完成'}' : '失败: ${r['message']}',
          error: !ok);
    });
  }

  void _detect() {
    final url = _firstLink;
    if (url.isEmpty) return _snack('请先输入链接', error: true);
    _run('解析', () async {
      await _syncCookie();
      final r = await DownloadEngine.instance
          .call('detect_link_info', {'platform': _platform, 'link': url});
      if (!mounted) return;
      if (r['success'] != true) {
        _snack('解析失败: ${r['message']}', error: true);
        return;
      }
      _log.success('解析成功: ${r['title'] ?? ''}', tag: _platform);
      _showLinkInfo(r);
    });
  }

  void _showLinkInfo(Map<String, dynamic> r) {
    final scheme = Theme.of(context).colorScheme;
    final author = r['author'] as Map<String, dynamic>?;
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (ctx) {
          return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.5,
              builder: (ctx, scroll) {
                return ListView(
                    controller: scroll,
                    padding: const EdgeInsets.all(24),
                    children: [
                      Text('链接信息',
                          style: Theme.of(ctx).textTheme.headlineSmall),
                      const SizedBox(height: 16),
                      if (r['title'] != null)
                        Card(
                          child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text('${r['title']}',
                                  style: Theme.of(ctx).textTheme.bodyLarge)),
                        ),
                      if (author != null) ...[
                        const SizedBox(height: 8),
                        Card(
                            child: ListTile(
                          leading: CircleAvatar(
                              backgroundColor: scheme.primaryContainer,
                              child: Icon(Icons.person,
                                  color: scheme.onPrimaryContainer)),
                          title: Text(author['nickname'] ?? ''),
                          subtitle: const Text('作者'),
                          trailing: FilledButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _downloadAccount(author['sec_uid'] ?? '',
                                    author['nickname'] ?? '');
                              },
                              icon: const Icon(Icons.download, size: 18),
                              label: const Text('下载全部')),
                        )),
                      ],
                    ]);
              });
        });
  }

  void _downloadAccount(String secUid, String nickname) {
    if (secUid.isEmpty) return;
    _run('下载 $nickname', () async {
      await _syncCookie();
      final sp = await _savePath();
      final r = await DownloadEngine.instance
          .callInBackground('batch_download_account', {
        'platform': 'douyin',
        'sec_uid': secUid,
        'nickname': nickname,
        'save_path': sp,
        'task_id': DownloadEngine.instance.newTaskId()
      });
      _snack(r['success'] == true ? '${r['message']}' : '失败: ${r['message']}',
          error: r['success'] != true);
    });
  }

  void _hotList() {
    _run('获取热榜', () async {
      await _syncCookie();
      final r = await DouyinBridge.getHotList();
      if (!mounted) return;
      final data = r['data'];
      if (r['success'] != true || data is! List || data.isEmpty) {
        _log.warn('热榜失败', tag: 'douyin');
        _snack('热榜获取失败', error: true);
        return;
      }
      _log.success('热榜: ${data.length} 条', tag: 'douyin');
      _showHotList(data);
    });
  }

  void _showHotList(List data) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (ctx) {
          return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.7,
              builder: (ctx, scroll) {
                return Column(children: [
                  Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(children: [
                        Icon(Icons.local_fire_department, color: scheme.error),
                        const SizedBox(width: 8),
                        Text('抖音热榜', style: Theme.of(ctx).textTheme.titleLarge),
                      ])),
                  const Divider(height: 1),
                  Expanded(
                      child: ListView.builder(
                          controller: scroll,
                          itemCount: data.length,
                          itemBuilder: (ctx, i) {
                            final item = data[i];
                            final title = item is Map
                                ? (item['word'] ?? '').toString()
                                : item.toString();
                            return ListTile(
                              leading: Container(
                                  width: 28,
                                  height: 28,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                      color: i < 3
                                          ? scheme.error
                                          : scheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(6)),
                                  child: Text('${i + 1}',
                                      style: TextStyle(
                                          color: i < 3
                                              ? scheme.onError
                                              : scheme.onSurface,
                                          fontWeight: i < 3
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          fontSize: 12))),
                              title: Text(title,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                            );
                          })),
                ]);
              });
        });
  }

  void _search() {
    showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('搜索'),
              content: TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                      hintText: '关键词', prefixIcon: Icon(Icons.search)),
                  onSubmitted: (v) => Navigator.pop(ctx, v)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('取消')),
                FilledButton(onPressed: () {}, child: const Text('搜索')),
              ],
            )).then((kw) {
      if (kw == null || kw.trim().isEmpty) return;
      _run('搜索 "$kw"', () async {
        await _syncCookie();
        final r = await DouyinBridge.searchGeneral(kw.trim());
        if (!mounted) return;
        final data = r['data'];
        if (r['success'] != true || data is! List) {
          _snack('搜索失败', error: true);
          return;
        }
        _snack('搜索到 ${data.length} 条');
      });
    });
  }

  void _simpleRun(String fn, String label) {
    final url = _firstLink;
    if (url.isEmpty) return _snack('请先输入链接', error: true);
    _run(label, () async {
      await _syncCookie();
      final sp = await _savePath();
      final r = await DownloadEngine.instance.callInBackground(fn, {
        'platform': _platform,
        'link': url,
        'save_path': sp,
        'task_id': DownloadEngine.instance.newTaskId()
      });
      _snack(
          r['success'] == true
              ? '$label: ${r['message']}'
              : '$label失败: ${r['message']}',
          error: r['success'] != true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar.medium(title: const Text('FNB Download'), actions: [
          IconButton(
            icon: Badge(
                isLabelVisible: _log.length > 0,
                label: Text('${_log.length}',
                    style: const TextStyle(fontSize: 10)),
                child: const Icon(Icons.terminal)),
            onPressed: () => setState(() => _showLog = !_showLog),
            tooltip: '日志',
          ),
          Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                      value: 'douyin',
                      label: Text('抖音'),
                      icon: Icon(Icons.video_library, size: 16)),
                  ButtonSegment(
                      value: 'xhs',
                      label: Text('小红书'),
                      icon: Icon(Icons.book, size: 16)),
                ],
                selected: {_platform},
                onSelectionChanged: (s) => setState(() => _platform = s.first),
                style: ButtonStyle(visualDensity: VisualDensity.compact),
                showSelectedIcon: false,
              )),
        ]),
        SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
                delegate: SliverChildListDelegate([
              // 输入卡片
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _link,
                              enabled: !_busy,
                              minLines: 2,
                              maxLines: 4,
                              decoration: InputDecoration(
                                hintText:
                                    '粘贴${_platform == 'douyin' ? "抖音" : "小红书"}链接...',
                                suffixIcon: _link.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear, size: 20),
                                        onPressed: () =>
                                            setState(() => _link.clear()))
                                    : null,
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 12),
                            Row(children: [
                              OutlinedButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () async {
                                          final d = await Clipboard.getData(
                                              Clipboard.kTextPlain);
                                          if (d?.text != null &&
                                              d!.text!.isNotEmpty) {
                                            setState(
                                                () => _link.text = d.text!);
                                          }
                                        },
                                  icon: const Icon(Icons.paste, size: 18),
                                  label: const Text('粘贴')),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                  onPressed: _busy ? null : _detect,
                                  icon:
                                      const Icon(Icons.info_outline, size: 18),
                                  label: const Text('解析')),
                              const Spacer(),
                              FilledButton.icon(
                                  onPressed: _busy ? null : _download,
                                  icon: _busy
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : const Icon(Icons.download),
                                  label: Text(_busy ? '处理中' : '下载')),
                            ]),
                          ]))),
              const SizedBox(height: 24),
              // 功能网格
              Text('快速操作',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: MediaQuery.of(context).size.width > 600 ? 3 : 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 2.5,
                children: [
                  if (_platform == 'douyin') ...[
                    _ActionTile(
                        icon: Icons.search,
                        label: '搜索',
                        color: scheme.primary,
                        onTap: _busy ? null : _search),
                    _ActionTile(
                        icon: Icons.local_fire_department,
                        label: '热榜',
                        color: scheme.error,
                        onTap: _busy ? null : _hotList),
                  ],
                  _ActionTile(
                      icon: Icons.comment,
                      label: '评论',
                      color: scheme.tertiary,
                      onTap: _busy
                          ? null
                          : () => _simpleRun('scrape_comments', '评论')),
                  _ActionTile(
                      icon: Icons.music_note,
                      label: '音频',
                      color: scheme.primary,
                      onTap: _busy
                          ? null
                          : () => _simpleRun('extract_audio', '音频')),
                  _ActionTile(
                      icon: Icons.image,
                      label: '封面',
                      color: scheme.secondary,
                      onTap: _busy
                          ? null
                          : () => _simpleRun('download_cover', '封面')),
                ],
              ),
              // 日志面板
              if (_showLog) ...[
                const SizedBox(height: 24),
                _LogPanel(log: _log, scheme: scheme),
              ],
              const SizedBox(height: 32),
            ]))),
      ]),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const _ActionTile(
      {required this.icon,
      required this.label,
      required this.color,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: color.withValues(alpha: 0.15))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 12),
              Text(label,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ]),
          )),
    );
  }
}

class _LogPanel extends StatelessWidget {
  final LogService log;
  final ColorScheme scheme;
  const _LogPanel({required this.log, required this.scheme});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
        valueListenable: log.notifier,
        builder: (context, _, __) {
          final entries = log.entries.reversed.take(20).toList();
          return Card(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                      child: Row(children: [
                        Icon(Icons.terminal, size: 18, color: scheme.primary),
                        const SizedBox(width: 8),
                        Text('操作日志',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        const Spacer(),
                        IconButton(
                            icon: const Icon(Icons.delete_sweep, size: 18),
                            onPressed: log.clear,
                            visualDensity: VisualDensity.compact),
                      ])),
                  const Divider(height: 1),
                  if (entries.isEmpty)
                    const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('暂无记录')))
                  else
                    ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 250),
                        child: ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          itemCount: entries.length,
                          itemBuilder: (ctx, i) {
                            final e = entries[i];
                            return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 1),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        '${e.timestamp.hour.toString().padLeft(2, '0')}:${e.timestamp.minute.toString().padLeft(2, '0')}:${e.timestamp.second.toString().padLeft(2, '0')}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                                color: scheme.outline,
                                                fontFamily: 'monospace')),
                                    const SizedBox(width: 8),
                                    Expanded(
                                        child: Text(e.message,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall)),
                                  ],
                                ));
                          },
                        )),
                ]),
          );
        });
  }
}
