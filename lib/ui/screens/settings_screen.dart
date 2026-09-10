import 'package:flutter/material.dart';
import '../../services/download/download_engine.dart';
import '../../services/storage/cookie_store.dart';

class SettingsScreen extends StatefulWidget {
  final ValueNotifier<ThemeMode> themeMode;
  const SettingsScreen({super.key, required this.themeMode});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, dynamic> _engine = {};
  CookieStore? _douyinCookie;
  CookieStore? _xhsCookie;

  @override
  void initState() {
    super.initState();
    _loadEngine();
    _loadCookies();
  }

  Future<void> _loadEngine() async {
    try {
      final s = await DownloadEngine.instance.getStatus();
      if (mounted) setState(() => _engine = s);
    } catch (_) {}
  }

  Future<void> _loadCookies() async {
    final dc = CookieStore(platform: 'douyin');
    final xc = CookieStore(platform: 'xhs');
    await dc.load();
    await xc.load();
    if (mounted) {
      setState(() {
        _douyinCookie = dc;
        _xhsCookie = xc;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: CustomScrollView(slivers: [
        const SliverAppBar.medium(title: Text('设置')),
        SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
                delegate: SliverChildListDelegate([
              const SizedBox(height: 8),
              // 外观
              _sectionHeader(context, Icons.palette, '外观'),
              const SizedBox(height: 8),
              _ThemeCard(themeMode: widget.themeMode),
              const SizedBox(height: 24),
              // Cookie
              _sectionHeader(context, Icons.key, '账号认证'),
              const SizedBox(height: 8),
              _cookieCard(context, 'douyin', '抖音', Icons.video_library,
                  scheme.primary, scheme.primaryContainer),
              const SizedBox(height: 8),
              _cookieCard(context, 'xhs', '小红书', Icons.book, scheme.tertiary,
                  scheme.tertiaryContainer),
              const SizedBox(height: 24),
              // 引擎
              _sectionHeader(context, Icons.memory, '引擎状态'),
              const SizedBox(height: 8),
              _engineCard(context),
              const SizedBox(height: 24),
              // 关于
              Center(
                  child: Column(children: [
                Icon(Icons.download_rounded, size: 48, color: scheme.primary),
                const SizedBox(height: 8),
                Text('FNB Download',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                Text('基于抖音 + 小红书 下载引擎',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.outline)),
                const SizedBox(height: 32),
              ])),
            ]))),
      ]),
    );
  }

  Widget _sectionHeader(BuildContext context, IconData icon, String title) {
    final scheme = Theme.of(context).colorScheme;
    return Row(children: [
      Icon(icon, size: 20, color: scheme.onSurfaceVariant),
      const SizedBox(width: 8),
      Text(title,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: scheme.onSurfaceVariant)),
    ]);
  }

  Widget _cookieCard(BuildContext context, String platform, String label,
      IconData icon, Color color, Color bg) {
    final scheme = Theme.of(context).colorScheme;
    final store = platform == 'douyin' ? _douyinCookie : _xhsCookie;
    final has = store?.hasActiveCookie ?? false;
    final name = store?.getActiveName() ?? '';
    final count = store?.getAll().length ?? 0;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: has
            ? BorderSide(color: scheme.primary.withValues(alpha: 0.2))
            : BorderSide.none,
      ),
      child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Row(children: [
              Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: bg, borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, color: color, size: 22)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(label,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                        has
                            ? '$name · ${store!.getActiveCookie()!.length} 字符'
                            : '未设置',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                has ? scheme.onSurfaceVariant : scheme.error)),
                  ])),
              Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                      color: has ? scheme.primary : scheme.error,
                      shape: BoxShape.circle)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: OutlinedButton.icon(
                onPressed: () => _editCookie(platform),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('编辑'),
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20))),
              )),
              if (has) ...[
                const SizedBox(width: 8),
                Expanded(
                    child: FilledButton.icon(
                  onPressed: () async {
                    final c = store!.getActiveCookie();
                    if (c != null) {
                      await DownloadEngine.instance.call(
                          'set_cookie', {'platform': platform, 'cookie': c});
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已同步到引擎')));
                      }
                    }
                  },
                  icon: const Icon(Icons.sync, size: 16),
                  label: const Text('同步'),
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20))),
                )),
              ],
            ]),
            if (count > 1)
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _showCookieList(platform),
                    child: Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 4, horizontal: 8),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text('共 $count 个 · 查看',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: scheme.primary)),
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right,
                              size: 14, color: scheme.primary),
                        ])),
                  )),
          ])),
    );
  }

  Widget _engineCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final available = _engine['available'] == true;
    final mode = _engine['mode']?.toString() ?? '检测中...';
    final python = _engine['python']?.toString() ?? '';
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: available
                          ? scheme.primaryContainer
                          : scheme.errorContainer,
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(
                      available ? Icons.check_circle : Icons.error_outline,
                      color: available
                          ? scheme.onPrimaryContainer
                          : scheme.onErrorContainer,
                      size: 22)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(available ? '引擎可用' : '引擎不可用',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: available ? null : scheme.error)),
                    const SizedBox(height: 2),
                    Text('$mode ${python.isNotEmpty ? "· Python" : ""}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ])),
              IconButton.filledTonal(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: () {
                    _loadEngine();
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('已刷新')));
                  }),
            ])));
  }

  void _editCookie(String platform) {
    final store = platform == 'douyin' ? _douyinCookie : _xhsCookie;
    final existingCookie = store?.getActiveCookie() ?? '';
    final existingName = store?.getActiveName() ?? '';
    final controller = TextEditingController(text: existingCookie);
    final nameController = TextEditingController(
        text: existingName.isNotEmpty
            ? existingName
            : 'Cookie ${DateTime.now().toString().substring(0, 16)}');
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text('设置 ${platform == 'douyin' ? "抖音" : "小红书"} Cookie'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                        labelText: '名称', hintText: '如：我的账号')),
                const SizedBox(height: 12),
                TextField(
                    controller: controller,
                    maxLines: 6,
                    autofocus: true,
                    decoration: const InputDecoration(hintText: '粘贴 Cookie')),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () async {
                      final cookie = controller.text.trim();
                      final name = nameController.text.trim().isEmpty
                          ? 'Cookie ${DateTime.now().toString().substring(0, 16)}'
                          : nameController.text.trim();
                      if (cookie.isNotEmpty) {
                        final currentStore =
                            platform == 'douyin' ? _douyinCookie : _xhsCookie;
                        if (currentStore != null) {
                          await currentStore.add(name, cookie);
                        } else {
                          final s = CookieStore(platform: platform);
                          await s.load();
                          await s.add(name, cookie);
                        }
                        await DownloadEngine.instance.call('set_cookie',
                            {'platform': platform, 'cookie': cookie});
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          await _loadCookies();
                        }
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已保存并同步')));
                        }
                      }
                    },
                    child: const Text('保存并同步')),
              ],
            ));
  }

  void _showCookieList(String platform) {
    final store = platform == 'douyin' ? _douyinCookie : _xhsCookie;
    if (store == null) return;
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (ctx) {
          return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.5,
              builder: (ctx, scroll) {
                final cookies = store.getAll();
                return Column(children: [
                  Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(children: [
                        Text('Cookie 列表',
                            style: Theme.of(ctx).textTheme.titleLarge),
                        const Spacer(),
                        Text('${cookies.length} 个',
                            style: Theme.of(ctx).textTheme.bodySmall),
                      ])),
                  const Divider(height: 1),
                  Expanded(
                      child: ListView.builder(
                          controller: scroll,
                          itemCount: cookies.length,
                          itemBuilder: (ctx, i) {
                            final c = cookies[i];
                            final isActive = c.name == store.getActiveName();
                            return ListTile(
                              leading: Icon(
                                  isActive
                                      ? Icons.check_circle
                                      : Icons.cookie_outlined,
                                  color: isActive
                                      ? scheme.primary
                                      : scheme.onSurfaceVariant),
                              title: Text(c.name,
                                  style: TextStyle(
                                      fontWeight: isActive
                                          ? FontWeight.w600
                                          : FontWeight.normal)),
                              subtitle: Text(
                                  '${c.cookie.length} 字符 · ${CookieStore.formatTime(c.updatedAt)}',
                                  style: Theme.of(ctx).textTheme.bodySmall),
                              trailing: IconButton(
                                  icon: Icon(Icons.delete_outline,
                                      size: 20, color: scheme.error),
                                  onPressed: () async {
                                    await store.remove(c.name);
                                    await _loadCookies();
                                    if (store.getAll().isEmpty && ctx.mounted) {
                                      Navigator.pop(ctx);
                                    }
                                  }),
                              onTap: () async {
                                await store.setActiveName(c.name);
                                await _loadCookies();
                                if (ctx.mounted) Navigator.pop(ctx);
                              },
                            );
                          })),
                ]);
              });
        });
  }
}

class _ThemeCard extends StatelessWidget {
  final ValueNotifier<ThemeMode> themeMode;
  const _ThemeCard({required this.themeMode});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
        valueListenable: themeMode,
        builder: (context, mode, _) {
          return Card(
              child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(children: [
                    for (final (icon, title, value) in [
                      (Icons.brightness_auto, '跟随系统', ThemeMode.system),
                      (Icons.light_mode, '浅色', ThemeMode.light),
                      (Icons.dark_mode, '深色', ThemeMode.dark),
                    ])
                      ListTile(
                        leading: Icon(icon,
                            color: value == mode
                                ? Theme.of(context).colorScheme.primary
                                : null),
                        title: Text(title),
                        trailing: value == mode
                            ? Icon(Icons.check_circle,
                                color: Theme.of(context).colorScheme.primary)
                            : null,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        onTap: () => themeMode.value = value,
                      ),
                  ])));
        });
  }
}
