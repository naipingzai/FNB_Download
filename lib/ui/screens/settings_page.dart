import 'package:flutter/material.dart';
import '../../services/download/download_engine.dart';
import '../../services/storage/cookie_store.dart';

/// 全新设置页 — 分区列表样式
class SettingsPage extends StatefulWidget {
  final ValueNotifier<ThemeMode> themeMode;
  const SettingsPage({super.key, required this.themeMode});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Map<String, dynamic> _engine = {};
  CookieStore? _douyinStore;
  CookieStore? _xhsStore;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dc = CookieStore(platform: 'douyin');
    final xc = CookieStore(platform: 'xhs');
    await dc.load();
    await xc.load();
    final eng = await DownloadEngine.instance.getStatus();
    if (mounted) {
      setState(() {
        _douyinStore = dc;
        _xhsStore = xc;
        _engine = eng;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CustomScrollView(slivers: [
      SliverAppBar.large(title: const Text('偏好设置')),
      SliverList.list(children: [
        // ── 外观 ──
        _header(context, '外观'),
        _appearanceTile(context),
        const SizedBox(height: 8),
        // ── 账号 ──
        _header(context, '账号'),
        _accountTile(context, 'douyin', '抖音', Icons.video_library_rounded),
        _accountTile(context, 'xhs', '小红书', Icons.auto_stories_rounded),
        const SizedBox(height: 8),
        // ── 引擎 ──
        _header(context, '引擎'),
        _engineTile(context),
        const SizedBox(height: 8),
        // ── 关于 ──
        _header(context, '关于'),
        _aboutCard(context, cs),
        const SizedBox(height: 32),
      ]),
    ]);
  }

  Widget _header(BuildContext ctx, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Text(text,
          style: Theme.of(ctx).textTheme.labelLarge?.copyWith(
              color: Theme.of(ctx).colorScheme.primary,
              fontWeight: FontWeight.w600)),
    );
  }

  Widget _appearanceTile(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: widget.themeMode,
      builder: (_, mode, __) {
        final labels = {
          ThemeMode.system: '跟随系统',
          ThemeMode.light: '浅色',
          ThemeMode.dark: '深色'
        };
        final icons = {
          ThemeMode.system: Icons.brightness_auto,
          ThemeMode.light: Icons.light_mode,
          ThemeMode.dark: Icons.dark_mode
        };
        return ListTile(
          leading: Icon(icons[mode]),
          title: const Text('颜色主题'),
          subtitle: Text(labels[mode] ?? ''),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _pickTheme(context, mode),
        );
      },
    );
  }

  void _pickTheme(BuildContext context, ThemeMode current) {
    showModalBottomSheet(
        context: context,
        builder: (ctx) {
          return SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final (icon, label, value) in [
              (Icons.brightness_auto, '跟随系统', ThemeMode.system),
              (Icons.light_mode, '浅色', ThemeMode.light),
              (Icons.dark_mode, '深色', ThemeMode.dark),
            ])
              RadioListTile<ThemeMode>(
                secondary: Icon(icon),
                title: Text(label),
                value: value,
                groupValue: current,
                onChanged: (v) {
                  if (v != null) {
                    widget.themeMode.value = v;
                    Navigator.pop(ctx);
                  }
                },
              ),
          ]));
        });
  }

  Widget _accountTile(
      BuildContext context, String platform, String label, IconData icon) {
    final store = platform == 'douyin' ? _douyinStore : _xhsStore;
    final has = store?.hasActiveCookie ?? false;
    final name = store?.getActiveName() ?? '';
    return ExpansionTile(
      leading:
          Icon(icon, color: has ? Theme.of(context).colorScheme.primary : null),
      title: Text(label),
      subtitle: Text(has ? name : '未配置',
          style: TextStyle(
              color: has ? null : Theme.of(context).colorScheme.error,
              fontSize: 13)),
      children: [
        if (store != null)
          ...store.getAll().map((c) => ListTile(
                dense: true,
                contentPadding: const EdgeInsets.only(left: 56, right: 16),
                title: Text(c.name,
                    style: TextStyle(
                        fontWeight: c.name == store.getActiveName()
                            ? FontWeight.w600
                            : FontWeight.normal)),
                subtitle: Text('${c.cookie.length} 字符',
                    style: const TextStyle(fontSize: 12)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (c.name == store.getActiveName())
                    Icon(Icons.check,
                        size: 18, color: Theme.of(context).colorScheme.primary),
                  IconButton(
                      icon: Icon(Icons.delete_outline,
                          size: 18, color: Theme.of(context).colorScheme.error),
                      onPressed: () async {
                        await store.remove(c.name);
                        await _load();
                      }),
                ]),
                onTap: () async {
                  await store.setActiveName(c.name);
                  await DownloadEngine.instance.call(
                      'set_cookie', {'platform': platform, 'cookie': c.cookie});
                  await _load();
                },
              )),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              Expanded(
                  child: OutlinedButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加'),
                onPressed: () => _addCookie(context, platform),
              )),
              if (has) ...[
                const SizedBox(width: 12),
                Expanded(
                    child: FilledButton.icon(
                  icon: const Icon(Icons.sync, size: 18),
                  label: const Text('同步'),
                  onPressed: () async {
                    final c = store!.getActiveCookie();
                    if (c != null) {
                      await DownloadEngine.instance.call(
                          'set_cookie', {'platform': platform, 'cookie': c});
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(content: Text('已同步')));
                      }
                    }
                  },
                )),
              ],
            ])),
      ],
    );
  }

  void _addCookie(BuildContext context, String platform) {
    final nameCtrl = TextEditingController();
    final cookieCtrl = TextEditingController();
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text('添加 ${platform == 'douyin' ? '抖音' : '小红书'} Cookie'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: '名称')),
                const SizedBox(height: 8),
                TextField(
                    controller: cookieCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Cookie')),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () async {
                      final name = nameCtrl.text.trim();
                      final cookie = cookieCtrl.text.trim();
                      if (name.isEmpty || cookie.isEmpty) return;
                      final store =
                          platform == 'douyin' ? _douyinStore : _xhsStore;
                      if (store != null) {
                        await store.add(name, cookie);
                        await DownloadEngine.instance.call('set_cookie',
                            {'platform': platform, 'cookie': cookie});
                        await _load();
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('保存')),
              ],
            ));
  }

  Widget _engineTile(BuildContext context) {
    final available = _engine['available'] == true;
    final mode = _engine['mode']?.toString() ?? '未知';
    return ListTile(
      leading: Icon(available ? Icons.check_circle : Icons.error,
          color: available
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.error),
      title: Text(available ? '引擎就绪' : '引擎未就绪'),
      subtitle: Text(mode),
      trailing: IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () async {
            await _load();
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('已刷新')));
            }
          }),
    );
  }

  Widget _aboutCard(BuildContext context, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Card(
        child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              CircleAvatar(
                  radius: 28,
                  backgroundColor: cs.primaryContainer,
                  child: Icon(Icons.download_done,
                      size: 28, color: cs.onPrimaryContainer)),
              const SizedBox(height: 12),
              Text('FNB Download',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('抖音 · 小红书 媒体下载工具',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.outline)),
              Text('v1.0.0',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: cs.outline)),
            ])),
      ),
    );
  }
}
