// 基础冒烟测试 — 仅保证应用骨架可加载
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_download_manager/app.dart';

void main() {
  testWidgets('应用可以构造', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FnbShell(themeMode: ValueNotifier<ThemeMode>(ThemeMode.system)),
      ),
    );
    expect(find.byType(FnbShell), findsOneWidget);
    // 三个底部导航目的地齐备
    expect(find.byType(NavigationDestination), findsNWidgets(3));
  });
}
