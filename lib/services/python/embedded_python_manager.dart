import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// 内嵌 Python 环境管理器
///
/// 所有平台均使用预打包的 Python 运行时，不依赖系统 Python：
/// - Android: Chaquopy (已在 build.gradle.kts 配置)
/// - iOS: CPython embedded (预编译静态库)
/// - Desktop: python-build-standalone (预下载到 python_runtime/ 目录)
///
/// 使用前请先运行 `bash scripts/download_python.sh` 预下载 Python 运行时
class EmbeddedPythonManager {
  static final EmbeddedPythonManager instance = EmbeddedPythonManager._();
  EmbeddedPythonManager._();

  static const _channel = MethodChannel('com.advancedownloader/python_bridge');

  bool _initialized = false;
  bool _available = false;
  String? _pythonHome;
  String? _pythonExecutable;
  String? _scriptsDir;
  String _version = '';

  /// Python 是否可用
  bool get isAvailable => _available;

  /// Python 版本
  String get version => _version;

  /// Python 可执行文件路径（Desktop 端）
  String? get executablePath => _pythonExecutable;

  /// Python Home 目录
  String? get pythonHome => _pythonHome;

  /// 脚本目录（assets/python 被解压后的路径）
  String? get scriptsDir => _scriptsDir;

  /// 初始化内嵌 Python 环境
  Future<bool> initialize() async {
    if (_initialized) return _available;
    _initialized = true;

    try {
      if (Platform.isAndroid) {
        return await _initAndroid();
      } else if (Platform.isIOS) {
        return await _initIOS();
      } else {
        return await _initDesktop();
      }
    } catch (e) {
      debugPrint('[EmbeddedPython] Initialization failed: $e');
      _available = false;
      return false;
    }
  }

  /// Android: 通过 Chaquopy 初始化
  Future<bool> _initAndroid() async {
    try {
      final result = await _channel.invokeMethod<bool>('isAvailable');
      _available = result ?? false;
      if (_available) {
        final status = await _channel.invokeMethod('getStatus');
        if (status != null) {
          _version = (status as Map)['version']?.toString() ?? '3.12';
        }
        await _extractPythonScripts();
      }
      debugPrint('[EmbeddedPython] Android init: available=$_available, version=$_version');
      return _available;
    } catch (e) {
      debugPrint('[EmbeddedPython] Android init failed: $e');
      _available = false;
      return false;
    }
  }

  /// iOS: 通过内嵌 CPython 初始化
  Future<bool> _initIOS() async {
    try {
      final result = await _channel.invokeMethod<bool>('isAvailable');
      _available = result ?? false;
      if (_available) {
        final status = await _channel.invokeMethod('getStatus');
        if (status != null) {
          _version = (status as Map)['version']?.toString() ?? '3.12';
        }
        await _extractPythonScripts();
      }
      debugPrint('[EmbeddedPython] iOS init: available=$_available, version=$_version');
      return _available;
    } catch (e) {
      debugPrint('[EmbeddedPython] iOS init failed: $e');
      _available = false;
      return false;
    }
  }

  /// Desktop: 使用预下载的 python-build-standalone
  Future<bool> _initDesktop() async {
    try {
      // 1. 优先查找项目本地的 python_runtime 目录
      final projectPythonDir = await _findProjectPythonRuntime();
      if (projectPythonDir != null) {
        return await _setupDesktopPython(projectPythonDir);
      }

      // 2. 回退到应用文档目录（兼容旧版本）
      final appDir = await getApplicationDocumentsDirectory();
      final appPythonDir = '${appDir.path}/python_embedded';
      final appPythonExe = _getDesktopPythonExecutable(appPythonDir);
      if (appPythonExe != null && await File(appPythonExe).exists()) {
        return await _setupDesktopPython(appPythonDir);
      }

      // 3. 未找到预下载的 Python
      debugPrint('[EmbeddedPython] Desktop: Python runtime not found!');
      debugPrint('[EmbeddedPython] Please run: bash scripts/download_python.sh');
      _available = false;
      return false;
    } catch (e) {
      debugPrint('[EmbeddedPython] Desktop init failed: $e');
      _available = false;
      return false;
    }
  }

  /// 查找项目本地的 Python 运行时目录
  Future<String?> _findProjectPythonRuntime() async {
    // 可能的路径列表
    final candidates = <String>[];

    // 1. 从当前工作目录查找
    final cwd = Directory.current.path;
    candidates.add('$cwd/python_runtime/${_getPlatformDir()}');

    // 2. 从可执行文件所在目录查找（release 模式）
    try {
      final exePath = Platform.resolvedExecutable;
      final exeDir = Directory(exePath).parent.path;
      // macOS app bundle: xxx.app/Contents/Frameworks/...
      if (Platform.isMacOS) {
        candidates.add('$exeDir/../Frameworks/python_runtime/${_getPlatformDir()}');
        candidates.add('$exeDir/../../../python_runtime/${_getPlatformDir()}');
      }
      candidates.add('$exeDir/python_runtime/${_getPlatformDir()}');
      // 上级目录
      candidates.add('${Directory(exeDir).parent.path}/python_runtime/${_getPlatformDir()}');
    } catch (_) {}

    // 3. 从应用文档目录查找
    try {
      final appDir = await getApplicationDocumentsDirectory();
      candidates.add('${appDir.path}/python_runtime/${_getPlatformDir()}');
    } catch (_) {}

    // 遍历候选路径
    for (final path in candidates) {
      final exe = _getDesktopPythonExecutable(path);
      if (exe != null && await File(exe).exists()) {
        debugPrint('[EmbeddedPython] Found Python runtime at: $path');
        return path;
      }
    }

    return null;
  }

  /// 获取当前平台对应的目录名
  String _getPlatformDir() {
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    return 'linux';
  }

  /// 设置 Desktop 端 Python
  Future<bool> _setupDesktopPython(String pythonDir) async {
    final pythonExe = _getDesktopPythonExecutable(pythonDir);
    if (pythonExe == null || !await File(pythonExe).exists()) {
      debugPrint('[EmbeddedPython] Python executable not found at: $pythonExe');
      return false;
    }

    _pythonExecutable = pythonExe;
    _pythonHome = pythonDir;

    // 设置执行权限 (Unix)
    if (!Platform.isWindows) {
      await Process.run('chmod', ['+x', pythonExe]);
    }

    _available = true;

    // 验证 Python 可用
    try {
      final result = await Process.run(pythonExe, ['--version']);
      if (result.exitCode == 0) {
        _version = (result.stdout as String).trim();
      }
    } catch (e) {
      debugPrint('[EmbeddedPython] Python version check failed: $e');
    }

    // 解压脚本
    await _extractPythonScripts();

    debugPrint('[EmbeddedPython] Desktop init: available=$_available, version=$_version, path=$_pythonExecutable');
    return true;
  }

  /// 获取 Desktop 端 Python 可执行文件路径
  String? _getDesktopPythonExecutable(String pythonDir) {
    if (Platform.isWindows) {
      return '$pythonDir/python.exe';
    } else if (Platform.isMacOS) {
      return '$pythonDir/bin/python3';
    } else if (Platform.isLinux) {
      return '$pythonDir/bin/python3';
    }
    return null;
  }

  /// 解压 Python 脚本到应用目录
  Future<void> _extractPythonScripts() async {
    try {
      // 1. 优先查找 python_runtime 目录中已打包的脚本
      if (_pythonHome != null) {
        final bundledScript = File('$_pythonHome/fnb_bridge.py');
        if (await bundledScript.exists()) {
          _scriptsDir = _pythonHome;
          debugPrint('[EmbeddedPython] Using bundled scripts at: $_scriptsDir');
          return;
        }
        // python_runtime/linux/ 的上级目录
        final parentDir = Directory(_pythonHome!).parent.path;
        final parentScript = File('$parentDir/fnb_bridge.py');
        if (await parentScript.exists()) {
          _scriptsDir = parentDir;
          debugPrint('[EmbeddedPython] Using bundled scripts at: $_scriptsDir');
          return;
        }
      }

      // 2. 查找可执行文件旁边的 python_runtime 目录
      if (_pythonExecutable != null) {
        final exeDir = Directory(_pythonExecutable!).parent.parent.path; // bin/.. = pythonHome
        final scriptDir = '$exeDir/..';
        final checkScript = File('$scriptDir/dy_bridge.py');
        if (await checkScript.exists()) {
          _scriptsDir = scriptDir;
          debugPrint('[EmbeddedPython] Using scripts from: $_scriptsDir');
          return;
        }
      }

      // 3. 从 Flutter assets 解压
      final appDir = await getApplicationDocumentsDirectory();
      final scriptsDir = Directory('${appDir.path}/python_scripts');
      if (!await scriptsDir.exists()) {
        await scriptsDir.create(recursive: true);
      }

      final scripts = ['dy_bridge.py', 'xhs_bridge.py', 'ks_bridge.py'];
      bool anyExtracted = false;
      for (final script in scripts) {
        try {
          final content = await rootBundle.loadString('assets/python/$script');
          final file = File('${scriptsDir.path}/$script');
          await file.writeAsString(content);
          anyExtracted = true;
        } catch (e) {
          debugPrint('[EmbeddedPython] Failed to extract $script: $e');
        }
      }

      if (anyExtracted) {
        _scriptsDir = scriptsDir.path;
        debugPrint('[EmbeddedPython] Scripts extracted to: $_scriptsDir');
      } else {
        // 4. 回退: 使用 python_runtime 目录
        _scriptsDir = _pythonHome;
        debugPrint('[EmbeddedPython] Fallback to pythonHome: $_scriptsDir');
      }
    } catch (e) {
      debugPrint('[EmbeddedPython] Script extraction failed: $e');
      _scriptsDir = _pythonHome;
    }
  }

  /// 调用 Python 函数
  Future<dynamic> callPython({
    required String module,
    required String function,
    List<dynamic> args = const [],
  }) async {
    if (!_available) {
      await initialize();
    }
    if (!_available) {
      throw Exception('Python environment not available. Please run: bash scripts/download_python.sh');
    }

    try {
      if (Platform.isAndroid || Platform.isIOS) {
        // Android/iOS: 通过 MethodChannel 调用 Chaquopy/内嵌 CPython
        return await _channel.invokeMethod('callPython', {
          'module': module,
          'function': function,
          'args': args,
        });
      } else {
        // Desktop: 通过 Process 调用内嵌 Python
        return await _callPythonProcess(module, function, args);
      }
    } catch (e) {
      debugPrint('[EmbeddedPython] callPython failed: $module.$function -> $e');
      rethrow;
    }
  }

  /// Desktop 端通过 Process 调用 Python
  Future<dynamic> _callPythonProcess(
    String module,
    String function,
    List<dynamic> args,
  ) async {
    if (_pythonExecutable == null) {
      throw Exception('Python executable not found');
    }

    final script = '''
import sys, json, os

# 添加脚本目录到 path
script_dir = "${_scriptsDir ?? ''}"
if script_dir and os.path.exists(script_dir):
    sys.path.insert(0, script_dir)

import $module

args = json.loads(sys.argv[1]) if len(sys.argv) > 1 else []
func = getattr($module, "$function")

if len(args) == 0:
    result = func()
elif len(args) == 1:
    result = func(args[0])
elif len(args) == 2:
    result = func(args[0], args[1])
elif len(args) == 3:
    result = func(args[0], args[1], args[2])
elif len(args) == 4:
    result = func(args[0], args[1], args[2], args[3])
else:
    result = func(*args)

if isinstance(result, dict) or isinstance(result, list):
    print(json.dumps(result, ensure_ascii=False))
elif result is None:
    print("{}")
else:
    print(json.dumps(str(result), ensure_ascii=False))
''';

    final tempScript = await File('${Directory.systemTemp.path}/py_embedded_$module.py')
        .writeAsString(script);

    try {
      final env = <String, String>{};
      if (_pythonHome != null) {
        env['PYTHONHOME'] = _pythonHome!;
        if (_scriptsDir != null) {
          env['PYTHONPATH'] = _scriptsDir!;
        }
      }

      final result = await Process.run(
        _pythonExecutable!,
        [tempScript.path, jsonEncode(args)],
        environment: env.isNotEmpty ? env : null,
      );

      if (result.exitCode != 0) {
        final stderr = result.stderr as String;
        debugPrint('[EmbeddedPython] stderr: $stderr');
        return {'success': false, 'message': stderr};
      }

      final stdout = (result.stdout as String).trim();
      try {
        return jsonDecode(stdout);
      } catch (_) {
        return stdout;
      }
    } finally {
      try {
        await tempScript.delete();
      } catch (_) {}
    }
  }

  /// 调用 Python 并返回 JSON Map
  Future<Map<String, dynamic>> callPythonJson({
    required String module,
    required String function,
    List<dynamic> args = const [],
  }) async {
    final result = await callPython(module: module, function: function, args: args);
    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
    if (result is String) {
      try {
        return Map<String, dynamic>.from(jsonDecode(result));
      } catch (_) {
        return {'success': false, 'message': result};
      }
    }
    return {'success': false, 'message': 'Unexpected result type: ${result.runtimeType}'};
  }

  /// 获取 Python 环境状态信息
  Future<Map<String, dynamic>> getStatus() async {
    if (!_initialized) {
      await initialize();
    }
    return {
      'available': _available,
      'version': _version,
      'platform': Platform.operatingSystem,
      'embedded': true,
      'pythonHome': _pythonHome,
      'scriptsDir': _scriptsDir,
      'executable': _pythonExecutable,
    };
  }

  /// 获取下载目录
  Future<String> getDownloadPath() async {
    try {
      if (Platform.isAndroid) {
        final result = await _channel.invokeMethod<String>('getDownloadPath');
        return result ?? '/storage/emulated/0/Download/DyDownload';
      } else {
        final appDir = await getApplicationDocumentsDirectory();
        final path = '${appDir.path}/downloads';
        await Directory(path).create(recursive: true);
        return path;
      }
    } catch (e) {
      return '/tmp/DyDownload';
    }
  }

  /// 清理内嵌 Python 环境（不删除预下载的运行时）
  Future<void> cleanup() async {
    try {
      // 只清理解压的脚本目录
      if (_scriptsDir != null) {
        final dir = Directory(_scriptsDir!);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
      _initialized = false;
      _available = false;
      _scriptsDir = null;
    } catch (e) {
      debugPrint('[EmbeddedPython] Cleanup failed: $e');
    }
  }
}
