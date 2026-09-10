import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Cookie 存储，支持多 Cookie 切换
class CookieStore {
  final String platform;
  List<CookieEntry> _cookies = [];
  String _activeName = '';

  CookieStore({required this.platform});

  String get _prefsKey => '${platform}_cookies';
  String get _activeKey => '${platform}_active_cookie';

  /// 加载所有 Cookie
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_prefsKey);
    _activeName = prefs.getString(_activeKey) ?? '';
    _cookies = [];
    if (json != null && json.isNotEmpty) {
      try {
        final list = jsonDecode(json) as List;
        _cookies = list
            .map((e) => CookieEntry.fromMap(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        _cookies = [];
      }
    }
    // 如果 activeName 指向不存在的 cookie，重置
    if (_activeName.isNotEmpty && !_cookies.any((e) => e.name == _activeName)) {
      _activeName = '';
      await _save();
    }
    // 如果没有 activeName 但有 cookie，自动选第一个
    if (_activeName.isEmpty && _cookies.isNotEmpty) {
      _activeName = _cookies.first.name;
      await _save();
    }
  }

  /// 保存到 SharedPreferences
  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(_cookies.map((e) => e.toMap()).toList()),
    );
    await prefs.setString(_activeKey, _activeName);
  }

  /// 获取所有 Cookie 列表
  List<CookieEntry> getAll() => List.unmodifiable(_cookies);

  /// Cookie 数量
  int get count => _cookies.length;

  /// 获取当前激活的 Cookie 名称
  String getActiveName() => _activeName;

  /// 是否有有效的 Cookie
  bool get hasActiveCookie {
    if (_activeName.isEmpty) return false;
    return _cookies.any((e) => e.name == _activeName);
  }

  /// 获取当前激活的 Cookie 内容
  String? getActiveCookie() {
    if (_activeName.isEmpty) return null;
    try {
      final entry = _cookies.firstWhere((e) => e.name == _activeName);
      return entry.cookie;
    } catch (_) {
      return null;
    }
  }

  /// 添加 Cookie 并自动激活
  Future<void> add(String name, String cookie) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    // 如果同名已存在则更新
    final idx = _cookies.indexWhere((e) => e.name == name);
    if (idx >= 0) {
      _cookies[idx] = CookieEntry(
        name: name,
        cookie: cookie,
        createdAt: _cookies[idx].createdAt,
        updatedAt: now,
      );
    } else {
      _cookies.add(CookieEntry(
        name: name,
        cookie: cookie,
        createdAt: now,
        updatedAt: now,
      ));
    }
    _activeName = name;
    await _save();
  }

  /// 设置激活的 Cookie
  Future<void> setActiveName(String name) async {
    _activeName = name;
    await _save();
  }

  /// 删除指定名称的 Cookie
  Future<void> remove(String name) async {
    _cookies.removeWhere((e) => e.name == name);
    if (_activeName == name) {
      _activeName = _cookies.isNotEmpty ? _cookies.first.name : '';
    }
    await _save();
  }

  /// 删除指定位置的 Cookie
  Future<void> removeAt(int index) async {
    if (index >= 0 && index < _cookies.length) {
      final removed = _cookies.removeAt(index);
      if (_activeName == removed.name) {
        _activeName = _cookies.isNotEmpty ? _cookies.first.name : '';
      }
      await _save();
    }
  }

  /// 清空所有 Cookie
  Future<void> clearAll() async {
    _cookies = [];
    _activeName = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    await prefs.remove(_activeKey);
  }

  /// 获取 Cookie 字段数
  int getKeyCount(String cookie) {
    return cookie.split(';').where((s) => s.contains('=')).length;
  }

  /// 格式化时间戳
  static String formatTime(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

/// Cookie 条目
class CookieEntry {
  final String name;
  final String cookie;
  final int createdAt;
  final int updatedAt;

  CookieEntry({
    required this.name,
    required this.cookie,
    int? createdAt,
    int? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
        updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toMap() => {
        'name': name,
        'cookie': cookie,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  factory CookieEntry.fromMap(Map<String, dynamic> map) => CookieEntry(
        name: map['name'] as String,
        cookie: map['cookie'] as String,
        createdAt: map['createdAt'] as int?,
        updatedAt: map['updatedAt'] as int?,
      );
}
