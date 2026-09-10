import 'bridge_base.dart';
import 'download_engine.dart';

/// 小红书下载桥接层（Linux: FFI→CPython / Android: Chaquopy）
/// 全部功能经 DownloadEngine → fnb_bridge 统一 JSON 协议分发。
class XhsBridge {
  static final DownloadEngine _engine = DownloadEngine.instance;

  /// 解析链接并下载单个笔记
  static Future<Map<String, dynamic>> parseAndDownload(
      String link, String savePath) async {
    return BridgeBase.executeTask(
      link: link,
      savePath: savePath,
      source: 'xhs',
      type: 'note',
      execute: (updateStatus, updateProgress) async {
        updateStatus('🔍 调用引擎解析小红书链接...');
        try {
          final result = await _engine.callInBackground('parse_and_download', {
            'platform': 'xhs',
            'link': link,
            'save_path': savePath,
            'task_id': BridgeBase.currentTaskId ?? '',
          });
          if (result['success'] == true) {
            updateStatus('✅ ${result['title'] ?? '下载完成'}');
          }
          return result;
        } catch (e) {
          return {'success': false, 'message': '调用失败: $e'};
        }
      },
    );
  }

  /// 检测用户信息（从笔记/主页链接）
  static Future<Map<String, dynamic>> detectUserInfo(String link) async {
    try {
      return await _engine.call('detect_user_info', {
        'platform': 'xhs',
        'link': link,
      });
    } catch (e) {
      return {'success': false, 'message': '检测失败: $e'};
    }
  }

  /// 批量下载作者全部笔记
  static Future<Map<String, dynamic>> batchDownloadUser(
      String userId, String nickname, String savePath) async {
    return BridgeBase.executeTask(
      link: 'user:$userId',
      savePath: savePath,
      source: 'xhs',
      type: 'note',
      execute: (updateStatus, updateProgress) async {
        updateStatus('📥 批量下载用户笔记: $nickname');
        try {
          final result = await _engine.callInBackground('batch_download_user', {
            'platform': 'xhs',
            'user_id': userId,
            'nickname': nickname,
            'save_path': savePath,
            'task_id': BridgeBase.currentTaskId ?? '',
          });
          if (result['success'] == true) {
            updateStatus('✅ ${result['message']}');
          }
          return result;
        } catch (e) {
          return {'success': false, 'message': '批量下载失败: $e'};
        }
      },
    );
  }

  /// 获取收藏夹列表
  static Future<Map<String, dynamic>> listCollections() async {
    try {
      return await _engine.call('list_collections', {'platform': 'xhs'});
    } catch (e) {
      return {'success': false, 'message': '获取收藏夹失败: $e'};
    }
  }

  /// 批量下载收藏夹
  static Future<Map<String, dynamic>> batchDownloadCollection(
      String collectId, String collectName, String savePath) async {
    return BridgeBase.executeTask(
      link: 'collection:$collectId',
      savePath: savePath,
      source: 'xhs',
      type: 'note',
      execute: (updateStatus, updateProgress) async {
        updateStatus('📥 下载收藏夹: $collectName');
        try {
          final result =
              await _engine.callInBackground('batch_download_collection', {
            'platform': 'xhs',
            'collect_id': collectId,
            'collect_name': collectName,
            'save_path': savePath,
            'task_id': BridgeBase.currentTaskId ?? '',
          });
          if (result['success'] == true) {
            updateStatus('✅ ${result['message']}');
          }
          return result;
        } catch (e) {
          return {'success': false, 'message': '收藏夹下载失败: $e'};
        }
      },
    );
  }

  /// 列出笔记全部图片（供选图下载）
  static Future<Map<String, dynamic>> listNoteImages(String link) async {
    try {
      return await _engine.call('list_note_images', {
        'platform': 'xhs',
        'link': link,
      });
    } catch (e) {
      return {'success': false, 'message': '获取图片列表失败: $e'};
    }
  }

  /// 下载指定序号的图片（如 "1,3,5"）
  static Future<Map<String, dynamic>> downloadSelectedImages(
      String link, String indices, String savePath) async {
    return BridgeBase.executeTask(
      link: 'images:$link',
      savePath: savePath,
      source: 'xhs',
      type: 'note',
      execute: (updateStatus, updateProgress) async {
        updateStatus('🖼️ 下载选中图片...');
        try {
          final result =
              await _engine.callInBackground('download_selected_images', {
            'platform': 'xhs',
            'link': link,
            'indices': indices,
            'save_path': savePath,
            'task_id': BridgeBase.currentTaskId ?? '',
          });
          if (result['success'] == true) {
            updateStatus('✅ ${result['message']}');
          }
          return result;
        } catch (e) {
          return {'success': false, 'message': '选图下载失败: $e'};
        }
      },
    );
  }

  /// 获取数据统计
  static Future<Map<String, dynamic>> getDataStats(String link) async {
    try {
      return await _engine.call('get_data_stats', {
        'platform': 'xhs',
        'link': link,
      });
    } catch (e) {
      return {'success': false, 'message': '获取数据失败: $e'};
    }
  }

  /// 设置 Cookie
  static Future<void> setCookie(String cookie) async {
    await _engine.call('set_cookie', {'platform': 'xhs', 'cookie': cookie});
  }

  /// 设置代理
  static Future<void> setProxy(String proxy) async {
    await _engine.call('set_proxy', {'platform': 'xhs', 'proxy': proxy});
  }
  /// 提取作品数据（不下载，原生 xhs 引擎）
  static Future<Map<String, dynamic>> extractData(String link) async {
    try {
      return await _engine.callInBackground('extract_data', {
        'platform': 'xhs',
        'link': link,
      });
    } catch (e) {
      return {'success': false, 'message': '数据提取失败: $e'};
    }
  }

}
