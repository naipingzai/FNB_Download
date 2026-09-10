import 'package:flutter/material.dart';

import 'app.dart' as app;
import 'core/task_manager/download_task_manager.dart';
import 'services/download/download_engine.dart';
import 'services/progress_polling_service.dart';
import 'services/storage/cookie_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FnbApp());
}

class FnbApp extends StatefulWidget {
  const FnbApp({super.key});

  @override
  State<FnbApp> createState() => _FnbAppState();
}

class _FnbAppState extends State<FnbApp> {
  final ValueNotifier<ThemeMode> _themeMode = ValueNotifier(ThemeMode.system);

  @override
  void initState() {
    super.initState();
    DownloadEngine.instance.initialize().then((_) => _syncAllCookies());
    ProgressPollingService.instance.start();
    DownloadTaskManager().init();
  }

  Future<void> _syncAllCookies() async {
    for (final platform in ['douyin', 'xhs']) {
      final store = CookieStore(platform: platform);
      await store.load();
      final cookie = store.getActiveCookie();
      if (cookie != null && cookie.isNotEmpty) {
        await DownloadEngine.instance
            .call('set_cookie', {'platform': platform, 'cookie': cookie});
      }
    }
  }

  @override
  void dispose() {
    ProgressPollingService.instance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lightScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF006874),
      brightness: Brightness.light,
    );
    final darkScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF006874),
      brightness: Brightness.dark,
    );
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeMode,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'FNB Download',
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: _buildTheme(lightScheme, Brightness.light),
          darkTheme: _buildTheme(darkScheme, Brightness.dark),
          home: app.FnbApp(themeMode: _themeMode),
        );
      },
    );
  }

  ThemeData _buildTheme(ColorScheme scheme, Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      typography: Typography.material2021(colorScheme: scheme),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 3,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w400,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: scheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorColor: scheme.primaryContainer,
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        backgroundColor: scheme.surface,
      ),
    );
  }
}
