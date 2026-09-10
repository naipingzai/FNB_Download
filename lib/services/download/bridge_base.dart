import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:uuid/uuid.dart';
import '../../core/task_manager/download_task.dart';
import '../../core/task_manager/download_task_manager.dart';

/// 平台 Bridge 基类
abstract class BridgeBase {
  static const _uuid = Uuid();
  static final DownloadTaskManager _taskManager = DownloadTaskManager();

  /// 当前正在执行的任务ID（供下载过程中更新状态用）
  static String? _activeTaskId;

  /// 当前任务ID只读访问（Bridge 调用引擎时作为 progress key 传入）
  static String? get currentTaskId => _activeTaskId;

  /// 每个任务的起始时间戳（用于按时间过滤目录文件）
  static final Map<String, int> _taskStartTimes = {};

  /// 更新当前任务标题（下载过程中调用，显示进度日志）
  static void updateTaskStatus(String status) {
    if (_activeTaskId == null) return;
    final task = _taskManager.getById(_activeTaskId!);
    if (task == null) return;
    _taskManager.updateTask(task.copyWith(title: status));
  }

  static Future<Map<String, dynamic>> executeTask({
    required String link,
    required String savePath,
    required String source,
    required String type,
    required Future<Map<String, dynamic>> Function(
            void Function(String status) updateStatus,
            void Function(int downloaded, int total) updateProgress)
        execute,
  }) async {
    // 去重：如果同 URL 的任务已完成或正在下载，不重复创建
    final existing = _taskManager.findByUrl(link);
    if (existing != null) {
      if (existing.status == TaskStatus.completed) {
        return {'success': true, 'title': existing.title, 'message': '已下载过'};
      }
      if (existing.status == TaskStatus.downloading) {
        return {'success': false, 'message': '该链接正在下载中'};
      }
    }

    final taskId = _uuid.v4();
    _activeTaskId = taskId;
    _taskStartTimes[taskId] = DateTime.now().millisecondsSinceEpoch;

    final task = DownloadTask(
      id: taskId,
      title: '🔍 解析链接中...',
      url: link,
      contentType: ContentType.fromString(type),
      status: TaskStatus.downloading,
      platform: PlatformType.fromId(source),
    );
    await _taskManager.addTask(task);

    void updateStatus(String status) {
      final cur = _taskManager.getById(taskId);
      if (cur != null) {
        _taskManager.updateTask(cur.copyWith(title: status));
      }
    }

    // 节流进度更新：避免频繁 notifyListeners
    DateTime lastProgressAt = DateTime.now();
    int lastTotal = -1;
    void updateProgress(int downloaded, int total) {
      final now = DateTime.now();
      // 1) 完成事件(total 首次出现或完成)立即更新 2) 节流 200ms
      final isComplete = total > 0 && downloaded >= total;
      final shouldUpdate = isComplete ||
          total != lastTotal ||
          now.difference(lastProgressAt).inMilliseconds > 200;
      if (!shouldUpdate) return;
      lastProgressAt = now;
      lastTotal = total;
      final cur = _taskManager.getById(taskId);
      if (cur != null) {
        _taskManager.updateTask(cur.copyWith(
          downloadedSize: downloaded,
          totalSize: total,
        ));
      }
    }

    try {
      final result = await execute(updateStatus, updateProgress);

      // 检查任务状态
      final cur = _taskManager.getById(taskId);
      if (cur == null) {
        _activeTaskId = null;
        _taskStartTimes.remove(taskId);
        return {'success': false, 'message': '已取消'};
      }
      if (cur.status == TaskStatus.paused) {
        _activeTaskId = null;
        return {'success': false, 'message': '已暂停'};
      }

      final success = result['success'] == true;
      final title = result['title']?.toString() ?? link;

      if (success) {
        // 1) 优先使用原生服务返回的 size（精确字节数）
        // 2) 回退到进度回调记录的最大值
        // 3) 最后回退：扫描本次任务时间戳后创建的文件
        var size = result['size'] as int? ?? cur.totalSize;
        final filePath = result['path']?.toString() ?? '';
        if (size <= 0 && filePath.isEmpty) {
          // 图集等多文件：result 未传 size，按时间戳扫描 authorDir 中本次产出
          size = await _sumRecentFiles(savePath, taskId);
        }
        // 多文件场景：显示张数
        final count = result['count'] as int?;
        final newTitle = (count != null && count > 1)
            ? '✅ $title  ($count 张 / 共 ${_formatBytes(size)})'
            : '✅ $title';
        await _taskManager.updateTask(cur.copyWith(
          title: newTitle,
          status: TaskStatus.completed,
          totalSize: size,
          downloadedSize: size,
          filePath: filePath,
        ));
      } else {
        await _taskManager.updateTask(cur.copyWith(
          title: '❌ ${result['message'] ?? '下载失败'}',
          status: TaskStatus.failed,
          errorMessage: result['message']?.toString() ?? '下载失败',
        ));
      }
      _activeTaskId = null;
      _taskStartTimes.remove(taskId);
      return result;
    } catch (e) {
      final cur = _taskManager.getById(taskId);
      if (cur != null) {
        await _taskManager.updateTask(cur.copyWith(
            title: '❌ $e',
            status: TaskStatus.failed,
            errorMessage: e.toString()));
      }
      _activeTaskId = null;
      _taskStartTimes.remove(taskId);
      return {'success': false, 'message': e.toString()};
    }
  }

  /// 扫描目录，汇总任务开始后创建的所有文件总字节数
  static Future<int> _sumRecentFiles(String dirPath, String taskId) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return 0;
    final startMs = _taskStartTimes[taskId];
    int total = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is! File) continue;
      try {
        final stat = await entity.stat();
        if (startMs == null ||
            stat.modified.millisecondsSinceEpoch >= startMs) {
          total += stat.size;
        }
      } catch (_) {}
    }
    return total;
  }

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  static String toJsonString(Map<String, dynamic> data) => jsonEncode(data);
}
