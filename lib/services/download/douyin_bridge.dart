import 'bridge_base.dart';
import 'download_engine.dart';

/// 抖音下载桥接层（Linux: FFI→CPython / Android: Chaquopy）
/// 全部功能经 DownloadEngine → fnb_bridge 统一 JSON 协议分发。
class DouyinBridge {
  static final DownloadEngine _engine = DownloadEngine.instance;

  /// 解析链接并下载单个作品
  static Future<Map<String, dynamic>> parseAndDownload(
      String link, String savePath) async {
    return BridgeBase.executeTask(
      link: link,
      savePath: savePath,
      source: 'douyin',
      type: 'video',
      execute: (updateStatus, updateProgress) async {
        updateStatus('🔍 调用引擎解析抖音链接...');
        try {
          final result = await _engine.callInBackground('parse_and_download', {
            'platform': 'douyin',
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

  /// 检测链接信息（提取作者/合集信息）
  static Future<Map<String, dynamic>> detectLinkInfo(String link) async {
    try {
      return await _engine.call('detect_link_info', {
        'platform': 'douyin',
        'link': link,
      });
    } catch (e) {
      return {'success': false, 'message': '检测失败: $e'};
    }
  }

  /// 批量下载作者作品
  static Future<Map<String, dynamic>> batchDownloadAccount(
      String secUid, String nickname, String savePath) async {
    return BridgeBase.executeTask(
      link: 'account:$secUid',
      savePath: savePath,
      source: 'douyin',
      type: 'video',
      execute: (updateStatus, updateProgress) async {
        updateStatus('📥 批量下载作者作品: $nickname');
        try {
          final result =
              await _engine.callInBackground('batch_download_account', {
            'platform': 'douyin',
            'sec_uid': secUid,
            'nickname': nickname,
            'save_path': savePath,
            'task_id': BridgeBase.currentTaskId ?? '',
          });
          if (result['success'] == true) {
            updateStatus('✅ ${result['title']} - ${result['message']}');
          }
          return result;
        } catch (e) {
          return {'success': false, 'message': '批量下载失败: $e'};
        }
      },
    );
  }

  /// 列出作者作品列表（不下载）
  static Future<Map<String, dynamic>> listAccountWorks(String secUid) async {
    try {
      return await _engine.call('list_account_works', {
        'platform': 'douyin',
        'sec_uid': secUid,
      });
    } catch (e) {
      return {'success': false, 'message': '获取作品列表失败: $e'};
    }
  }

  /// 获取收藏夹列表
  static Future<Map<String, dynamic>> listCollectFolders() async {
    try {
      return await _engine.call('list_collect_folders', {'platform': 'douyin'});
    } catch (e) {
      return {'success': false, 'message': '获取收藏夹失败: $e'};
    }
  }

  /// 批量下载收藏夹
  static Future<Map<String, dynamic>> batchDownloadCollect(
      String collectId, String collectName, String savePath) async {
    return BridgeBase.executeTask(
      link: 'collect:$collectId',
      savePath: savePath,
      source: 'douyin',
      type: 'video',
      execute: (updateStatus, updateProgress) async {
        updateStatus('📥 下载收藏夹: $collectName');
        try {
          final result =
              await _engine.callInBackground('batch_download_collect', {
            'platform': 'douyin',
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

  /// 批量下载合集
  static Future<Map<String, dynamic>> batchDownloadMix(
      String mixId, String mixName, String savePath) async {
    return BridgeBase.executeTask(
      link: 'mix:$mixId',
      savePath: savePath,
      source: 'douyin',
      type: 'video',
      execute: (updateStatus, updateProgress) async {
        updateStatus('📥 下载合集: $mixName');
        try {
          final result = await _engine.callInBackground('batch_download_mix', {
            'platform': 'douyin',
            'mix_id': mixId,
            'mix_name': mixName,
            'save_path': savePath,
            'task_id': BridgeBase.currentTaskId ?? '',
          });
          if (result['success'] == true) {
            updateStatus('✅ ${result['message']}');
          }
          return result;
        } catch (e) {
          return {'success': false, 'message': '合集下载失败: $e'};
        }
      },
    );
  }

  /// 从历史记录重新下载
  static Future<Map<String, dynamic>> redownloadFromHistory(
      String savePath) async {
    return BridgeBase.executeTask(
      link: 'history:redownload',
      savePath: savePath,
      source: 'douyin',
      type: 'video',
      execute: (updateStatus, updateProgress) async {
        updateStatus('🔄 从历史记录重新下载...');
        try {
          final result =
              await _engine.callInBackground('redownload_from_history', {
            'platform': 'douyin',
            'save_path': savePath,
            'task_id': BridgeBase.currentTaskId ?? '',
          });
          if (result['success'] == true) {
            updateStatus('✅ ${result['message']}');
          }
          return result;
        } catch (e) {
          return {'success': false, 'message': '重新下载失败: $e'};
        }
      },
    );
  }

  /// 录制直播
  static Future<Map<String, dynamic>> recordLive(
      String liveUrl, String savePath) async {
    return BridgeBase.executeTask(
      link: 'live:$liveUrl',
      savePath: savePath,
      source: 'douyin',
      type: 'live',
      execute: (updateStatus, updateProgress) async {
        updateStatus('🎥 开始录制直播...');
        try {
          final result = await _engine.callInBackground('record_live', {
            'platform': 'douyin',
            'live_url': liveUrl,
            'save_path': savePath,
            'task_id': BridgeBase.currentTaskId ?? '',
          });
          if (result['success'] == true) {
            updateStatus('✅ ${result['message']}');
          }
          return result;
        } catch (e) {
          return {'success': false, 'message': '直播录制失败: $e'};
        }
      },
    );
  }

  /// 采集评论
  static Future<Map<String, dynamic>> scrapeComments(
      String link, String savePath) async {
    return BridgeBase.executeTask(
      link: 'comments:$link',
      savePath: savePath,
      source: 'douyin',
      type: 'video',
      execute: (updateStatus, updateProgress) async {
        updateStatus('💬 开始采集评论...');
        try {
          final result = await _engine.callInBackground('scrape_comments', {
            'link': link,
            'save_path': savePath,
            'task_id': BridgeBase.currentTaskId ?? '',
          });
          if (result['success'] == true) {
            updateStatus('✅ ${result['message']}');
          }
          return result;
        } catch (e) {
          return {'success': false, 'message': '评论采集失败: $e'};
        }
      },
    );
  }

  /// 下载封面
  static Future<Map<String, dynamic>> downloadCover(
      String link, String savePath) async {
    return BridgeBase.executeTask(
      link: 'cover:$link',
      savePath: savePath,
      source: 'douyin',
      type: 'video',
      execute: (updateStatus, updateProgress) async {
        updateStatus('🖼️ 下载封面...');
        try {
          final result = await _engine.callInBackground('download_cover', {
            'platform': 'douyin',
            'link': link,
            'save_path': savePath,
            'task_id': BridgeBase.currentTaskId ?? '',
          });
          if (result['success'] == true) {
            updateStatus('✅ ${result['message']}');
          }
          return result;
        } catch (e) {
          return {'success': false, 'message': '封面下载失败: $e'};
        }
      },
    );
  }

  /// 提取音频
  static Future<Map<String, dynamic>> extractAudio(
      String link, String savePath) async {
    return BridgeBase.executeTask(
      link: 'audio:$link',
      savePath: savePath,
      source: 'douyin',
      type: 'video',
      execute: (updateStatus, updateProgress) async {
        updateStatus('🎵 提取音频...');
        try {
          final result = await _engine.callInBackground('extract_audio', {
            'platform': 'douyin',
            'link': link,
            'save_path': savePath,
            'task_id': BridgeBase.currentTaskId ?? '',
          });
          if (result['success'] == true) {
            updateStatus('✅ ${result['message']}');
          }
          return result;
        } catch (e) {
          return {'success': false, 'message': '音频提取失败: $e'};
        }
      },
    );
  }

  /// 获取数据统计
  static Future<Map<String, dynamic>> getDataStats(String link) async {
    try {
      return await _engine.call('get_data_stats', {
        'platform': 'douyin',
        'link': link,
      });
    } catch (e) {
      return {'success': false, 'message': '获取数据失败: $e'};
    }
  }

  /// 获取热榜数据
  static Future<Map<String, dynamic>> getHotList() async {
    try {
      return await _engine.call('get_hot_list', {});
    } catch (e) {
      return {'success': false, 'message': '获取热榜失败: $e'};
    }
  }

  /// 设置 Cookie
  static Future<void> setCookie(String cookie) async {
    await _engine
        .call('set_cookie', {'platform': 'douyin', 'cookie': cookie});
  }

  /// 设置代理
  static Future<void> setProxy(String proxy) async {
    await _engine.call('set_proxy', {'platform': 'douyin', 'proxy': proxy});
  }
  /// 综合搜索（原生 tkd Search 接口：视频/用户/直播混合结果）
  static Future<Map<String, dynamic>> searchGeneral(String keyword) async {
    try {
      return await _engine.callInBackground('search_general', {
        'platform': 'douyin',
        'keyword': keyword,
      });
    } catch (e) {
      return {'success': false, 'message': '搜索失败: $e'};
    }
  }

  /// 获取引擎后端状态（native=完整版 / legacy=精简版）
  static Future<Map<String, dynamic>> getBackendStatus() async {
    try {
      return await _engine.call('status', {});
    } catch (e) {
      return {'success': false, 'message': '$e'};
    }
  }

}
