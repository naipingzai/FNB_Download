import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/download/download_engine.dart';

/// M3 任务页 — 实时轮询 Python 引擎进度注册表
class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  Map<String, Map<String, dynamic>> _tasks = {};
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer =
        Timer.periodic(const Duration(milliseconds: 800), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final data = await DownloadEngine.instance.pollProgress();
    if (mounted) setState(() => _tasks = data);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = _tasks.entries.toList()
      ..sort((a, b) => (b.value['ts'] ?? 0).compareTo(a.value['ts'] ?? 0));

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: const Text('任务'),
            actions: [
              if (items.isNotEmpty)
                IconButton(
                  tooltip: '清除已完成',
                  icon: const Icon(Icons.cleaning_services_outlined),
                  onPressed: () async {
                    await DownloadEngine.instance.call('clear_progress', {});
                    _refresh();
                  },
                ),
            ],
          ),
          if (items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(scheme: scheme),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) => _TaskCard(
                  id: items[i].key,
                  data: items[i].value,
                  onPause: () =>
                      DownloadEngine.instance.pauseTask(items[i].key),
                  onResume: () =>
                      DownloadEngine.instance.resumeTask(items[i].key),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final ColorScheme scheme;
  const _EmptyState({required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.cloud_download_outlined,
                size: 48, color: scheme.outline),
          ),
          const SizedBox(height: 20),
          Text('暂无任务',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text('下载中的任务将实时显示在这里',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.outline)),
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final String id;
  final Map<String, dynamic> data;
  final VoidCallback onPause;
  final VoidCallback onResume;

  const _TaskCard({
    required this.id,
    required this.data,
    required this.onPause,
    required this.onResume,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = data['status']?.toString() ?? '';
    final title = data['title']?.toString() ?? '任务';
    final downloaded = (data['downloaded'] ?? 0) as num;
    final total = (data['total'] ?? 0) as num;
    final progress = total > 0 ? (downloaded / total).clamp(0.0, 1.0) : null;
    final running = status == 'running' || status == 'parsing';
    final paused = status == 'pausing';
    final done = status == 'done';
    final failed = status == 'failed';

    Color statusColor;
    String statusText;
    IconData statusIcon;
    if (done) {
      statusColor = scheme.primary;
      statusText = '已完成';
      statusIcon = Icons.check_circle_rounded;
    } else if (failed) {
      statusColor = scheme.error;
      statusText = '失败';
      statusIcon = Icons.error_rounded;
    } else if (paused) {
      statusColor = scheme.tertiary;
      statusText = '暂停中';
      statusIcon = Icons.pause_circle_rounded;
    } else {
      statusColor = scheme.secondary;
      statusText = status == 'parsing' ? '解析中' : '下载中';
      statusIcon = Icons.downloading_rounded;
    }

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: done
            ? BorderSide(color: scheme.primary.withValues(alpha: 0.3))
            : failed
                ? BorderSide(color: scheme.error.withValues(alpha: 0.3))
                : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (running || paused)
                  IconButton.filledTonal(
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(paused
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded),
                    onPressed: paused ? onResume : onPause,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            // Status + size
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    statusText,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: statusColor, fontWeight: FontWeight.w600),
                  ),
                ),
                const Spacer(),
                if (total > 0)
                  Text(
                    '${_formatBytes(downloaded.toInt())} / ${_formatBytes(total.toInt())}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
            // Progress bar
            if (running || paused) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor:
                      scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                ),
              ),
              if (progress != null) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${(progress * 100).toStringAsFixed(1)}%',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
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
}
