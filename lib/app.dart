import 'package:flutter/material.dart';
import 'ui/screens/home_page.dart';
import 'ui/screens/tasks_screen.dart';
import 'ui/screens/settings_page.dart';

/// M3 应用壳 — 底部导航栏
class FnbApp extends StatefulWidget {
  final ValueNotifier<ThemeMode> themeMode;
  const FnbApp({super.key, required this.themeMode});
  @override
  State<FnbApp> createState() => _FnbAppState();
}

class _FnbAppState extends State<FnbApp> {
  int _pageIndex = 0;

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.link_outlined),
      selectedIcon: Icon(Icons.link),
      label: '首页',
    ),
    NavigationDestination(
      icon: Icon(Icons.download_outlined),
      selectedIcon: Icon(Icons.download),
      label: '任务',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: '设置',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: NavigationBar(
        selectedIndex: _pageIndex,
        onDestinationSelected: (i) => setState(() => _pageIndex = i),
        destinations: _destinations,
      ),
      body: IndexedStack(
        index: _pageIndex,
        children: [
          const HomePage(),
          const TasksScreen(),
          SettingsPage(themeMode: widget.themeMode),
        ],
      ),
    );
  }
}
