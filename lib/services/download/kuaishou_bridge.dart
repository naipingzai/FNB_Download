import 'bridge_base.dart';
import 'download_engine.dart';

/// 快手下载桥接层（Linux: FFI→CPython / Android: Chaquopy）
class KuaishouBridge {
  static final DownloadEngine _engine = DownloadEngine.instance;

  /// 解析链接并下载单个作品
  static Future<Map<String, dynamic>> parseAndDownload(
      String link, String savePath) async {
    return BridgeBase.executeTask(
      link: link,
      savePath: savePath,
      source: 'kuaishou',
      type: 'video',
      execute: (updateStatus, updateProgress) async {
        updateStatus('🐍 调用引擎解析快手链接...');
        try {
          final result = await _engine.callInBackground('parse_and_download', {
            'platform': 'kuaishou',
            'link': link,
            'save_path': savePath,
            'task_id': BridgeBase.currentTaskId ?? '',
          });
          if (result['success'] == true) {
            updateStatus('✅ ${result['title'] ?? '下载完成'}');
          }
          return result;
        } catch (e) {
          return {'success': false, 'message': '引擎调用失败: $e'};
        }
      },
    );
  }

  /// 设置 Cookie
  static Future<void> setCookie(String cookie) async {
    await _engine
        .call('set_cookie', {'platform': 'kuaishou', 'cookie': cookie});
  }

  /// 设置代理
  static Future<void> setProxy(String proxy) async {
    await _engine.call('set_proxy', {'platform': 'kuaishou', 'proxy': proxy});
  }
}
