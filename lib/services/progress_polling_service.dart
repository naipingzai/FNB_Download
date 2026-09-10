import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/task_manager/download_task.dart';
import '../core/task_manager/download_task_manager.dart';
import 'download/download_engine.dart';

/// 进度轮询服务
/// 周期性读取 fnb_bridge 的进度注册表（progress.json / MethodChannel），
/// 桥接到 DownloadTaskManager 刷新 UI。
///
/// Linux FFI 模式下轮询只是读文件，不进 Python；
/// 真正的下载进度由 Python 长任务在后台线程写文件。
class ProgressPollingService {
  ProgressPollingService._();
  static final ProgressPollingService instance = ProgressPollingService._();

  final DownloadEngine _engine = DownloadEngine.instance;
  final DownloadTaskManager _taskManager = DownloadTaskManager();

  Timer? _timer;
  bool _polling = false;

  static const _interval = Duration(milliseconds: 800);

  void start() {
    _timer ??= Timer.periodic(_interval, (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    if (_polling) return;
    _polling = true;
    try {
      final progress = await _engine.pollProgress();
      if (progress.isEmpty) return;

      for (final entry in progress.entries) {
        final taskId = entry.key;
        final data = entry.value;
        final task = _taskManager.getById(taskId);
        if (task == null) continue;

        final status = data['status']?.toString() ?? '';
        final downloaded = (data['downloaded'] as num?)?.toInt() ?? 0;
        final total = (data['total'] as num?)?.toInt() ?? 0;
        final title = data['title']?.toString() ?? '';

        TaskStatus? newStatus;
        switch (status) {
          case 'pausing':
            newStatus = TaskStatus.paused;
            break;
          case 'done':
            newStatus = TaskStatus.completed;
            break;
          case 'failed':
            newStatus = TaskStatus.failed;
            break;
          case 'parsing':
          case 'running':
            if (task.status != TaskStatus.downloading &&
                task.status != TaskStatus.paused) {
              newStatus = TaskStatus.downloading;
            }
            break;
        }

        final sizeChanged =
            downloaded != task.downloadedSize || total != task.totalSize;
        if (newStatus != null && newStatus != task.status) {
          await _taskManager.updateTask(task.copyWith(
            status: newStatus,
            downloadedSize: downloaded,
            totalSize: total,
            title: title.isNotEmpty ? title : task.title,
          ));
        } else if (sizeChanged) {
          await _taskManager.updateTask(task.copyWith(
            downloadedSize: downloaded,
            totalSize: total,
            title: title.isNotEmpty ? title : null,
          ));
        }
      }

      // 清理终态条目（防止 progress.json 无限膨胀）
      final finished = progress.entries
          .where((e) =>
              e.value['status'] == 'done' || e.value['status'] == 'failed')
          .map((e) => e.key)
          .toList();
      for (final taskId in finished) {
        final task = _taskManager.getById(taskId);
        if (task != null &&
            (task.status == TaskStatus.completed ||
                task.status == TaskStatus.failed)) {
          await _engine.call('clear_progress', {'task_id': taskId});
        }
      }
    } catch (e) {
      debugPrint('[ProgressPolling] $e');
    } finally {
      _polling = false;
    }
  }
}
