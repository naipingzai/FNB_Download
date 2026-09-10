import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'embedded_python_manager.dart';

/// 统一的 Python 运行器
/// 所有平台均使用内嵌 Python 环境，不依赖系统 Python
/// - Android: Chaquopy (已在 build.gradle.kts 配置)
/// - iOS: CPython embedded (预编译静态库)
/// - Desktop: python-build-standalone (自动下载安装)
class PythonRunner {
  static final PythonRunner instance = PythonRunner._();
  PythonRunner._();

  final EmbeddedPythonManager _embedded = EmbeddedPythonManager.instance;
  bool _initialized = false;

  /// 初始化 Python 环境（自动选择平台对应的内嵌方案）
  Future<bool> _ensureInitialized() async {
    if (_initialized) return _embedded.isAvailable;
    _initialized = true;
    return await _embedded.initialize();
  }

  /// Python 环境是否可用
  Future<bool> get isAvailable async {
    await _ensureInitialized();
    return _embedded.isAvailable;
  }

  /// 获取 Python 环境状态信息
  Future<Map<String, dynamic>> getStatus() async {
    await _ensureInitialized();
    return await _embedded.getStatus();
  }

  /// 获取下载目录
  Future<String> getDownloadPath() async {
    await _ensureInitialized();
    return await _embedded.getDownloadPath();
  }

  /// 调用 Python 函数
  Future<dynamic> callPython({
    required String module,
    required String function,
    List<dynamic> args = const [],
  }) async {
    await _ensureInitialized();
    try {
      return await _embedded.callPython(
        module: module,
        function: function,
        args: args,
      );
    } catch (e) {
      debugPrint('[PythonRunner] callPython failed: $module.$function -> $e');
      rethrow;
    }
  }

  /// 调用 Python 并返回 JSON 解析后的 Map
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

  /// 设置 Cookie（抖音）
  Future<void> setDouyinCookie(String cookie) async {
    await callPython(module: 'fnb_bridge', function: 'call', args: ['set_cookie', '{"platform": "douyin", "cookie": "\$cookie"}']);
  }

  /// 设置 Cookie（小红书）
  Future<void> setXhsCookie(String cookie) async {
    await callPython(module: 'fnb_bridge', function: 'call', args: ['set_cookie', '{"platform": "xhs", "cookie": "\$cookie"}']);
  }

  /// 设置 Cookie（快手）
  Future<void> setKuaishouCookie(String cookie) async {
    await callPython(module: 'fnb_bridge', function: 'call', args: ['set_cookie', '{"platform": "kuaishou", "cookie": "\$cookie"}']);
  }

  /// 设置代理（抖音）
  Future<void> setDouyinProxy(String proxy) async {
    await callPython(module: 'fnb_bridge', function: 'call', args: ['set_proxy', '{"platform": "douyin", "proxy": "\$proxy"}']);
  }

  /// 设置代理（小红书）
  Future<void> setXhsProxy(String proxy) async {
    await callPython(module: 'xhs_bridge', function: 'set_proxy', args: [proxy]);
  }

  /// 设置代理（快手）
  Future<void> setKuaishouProxy(String proxy) async {
    await callPython(module: 'ks_bridge', function: 'set_proxy', args: [proxy]);
  }

  /// 清理内嵌 Python 环境
  Future<void> cleanup() async {
    await _embedded.cleanup();
    _initialized = false;
  }
}
