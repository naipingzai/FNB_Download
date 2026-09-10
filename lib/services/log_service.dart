import 'package:flutter/foundation.dart';

/// 操作日志服务 - 记录所有引擎操作和状态变化
class LogService {
  LogService._();
  static final LogService instance = LogService._();

  final List<LogEntry> _entries = [];
  final ValueNotifier<int> notifier = ValueNotifier(0);

  static const int maxEntries = 200;

  List<LogEntry> get entries => List.unmodifiable(_entries);
  int get length => _entries.length;

  void info(String message, {String? tag}) {
    _add(LogLevel.info, message, tag: tag);
  }

  void warn(String message, {String? tag}) {
    _add(LogLevel.warn, message, tag: tag);
  }

  void error(String message, {String? tag}) {
    _add(LogLevel.error, message, tag: tag);
  }

  void success(String message, {String? tag}) {
    _add(LogLevel.success, message, tag: tag);
  }

  void _add(LogLevel level, String message, {String? tag}) {
    final entry = LogEntry(
      level: level,
      message: message,
      tag: tag,
      timestamp: DateTime.now(),
    );
    _entries.add(entry);
    if (_entries.length > maxEntries) {
      _entries.removeAt(0);
    }
    debugPrint('[Log] $message');
    notifier.value++;
  }

  void clear() {
    _entries.clear();
    notifier.value++;
  }
}

enum LogLevel { info, warn, error, success }

class LogEntry {
  final LogLevel level;
  final String message;
  final String? tag;
  final DateTime timestamp;

  LogEntry({
    required this.level,
    required this.message,
    this.tag,
    required this.timestamp,
  });
}
