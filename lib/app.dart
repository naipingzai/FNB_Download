import 'package:flutter/material.dart';
import 'ui/screens/home_page.dart';
import 'ui/screens/settings_page.dart';

/// 全新 M3 应用壳 — Drawer 导航 + 搜索优先
class FnbApp extends StatefulWidget {
  final ValueNotifier<ThemeMode> themeMode;
  const FnbApp({super.key, required this.themeMode});
  @override
  State<FnbApp> createState() => _FnbAppState();
}

class _FnbAppState extends State<FnbApp> {
  int _pageIndex = 0;
  final _drawerKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      key: _drawerKey,
      drawer: NavigationDrawer(
        selectedIndex: _pageIndex,
        onDestinationSelected: (i) {
          setState(() => _pageIndex = i);
          Navigator.pop(context);
        },
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 28, 16, 20),
            child: Row(children: [
              Icon(Icons.get_app, size: 28, color: cs.primary),
              const SizedBox(width: 12),
              Text('FNB Download',
                  style: Theme.of(context).textTheme.titleMedium),
            ]),
          ),
          const NavigationDrawerDestination(
              icon: Icon(Icons.link), label: Text('下载任务')),
          const NavigationDrawerDestination(
              icon: Icon(Icons.history), label: Text('历史记录')),
          const Padding(
              padding: EdgeInsets.fromLTRB(28, 16, 28, 10), child: Divider()),
          const NavigationDrawerDestination(
              icon: Icon(Icons.tune), label: Text('偏好设置')),
        ],
      ),
      body: IndexedStack(
        index: _pageIndex,
        children: [
          HomePage(onOpenDrawer: () => _drawerKey.currentState?.openDrawer()),
          _HistoryPlaceholder(),
          SettingsPage(themeMode: widget.themeMode),
        ],
      ),
    );
  }
}

class _HistoryPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomScrollView(slivers: [
      SliverAppBar.large(title: const Text('历史记录')),
      const SliverFillRemaining(child: Center(child: Text('下载记录将显示在这里'))),
    ]);
  }
}
