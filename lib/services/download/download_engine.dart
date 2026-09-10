import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// 下载引擎门面 — Linux / Android 双通道统一入口
class DownloadEngine {
  DownloadEngine._();
  static final DownloadEngine instance = DownloadEngine._();

  static const _channel = MethodChannel('com.advancedownloader/python_bridge');
  static const _uuid = Uuid();

  EngineMode? _mode;
  bool _initializing = false;
  bool _readyOk = false;
  final Completer<bool> _ready = Completer<bool>();

  String _appDataDir = '';
  String _pythonExe = '';

  Process? _process;
  Completer<String>? _responseCompleter;
  final List<String> _stderrLog = [];

  EngineMode? get mode => _mode;
  bool get isReady => _readyOk;

  EngineMode detectMode() {
    if (Platform.isAndroid) return EngineMode.androidChaquopy;
    if (Platform.isLinux) return EngineMode.linuxSubprocess;
    return EngineMode.unsupported;
  }

  Future<bool> initialize() async {
    if (_ready.isCompleted) return _ready.future;
    if (_initializing) return _ready.future;
    _initializing = true;
    try {
      _mode = detectMode();
      switch (_mode!) {
        case EngineMode.linuxSubprocess:
          await _initLinux();
          break;
        case EngineMode.androidChaquopy:
          await _initAndroid();
          break;
        case EngineMode.unsupported:
          debugPrint('[DownloadEngine] Unsupported platform');
      }
    } catch (e) {
      debugPrint('[DownloadEngine] Init failed: $e');
    }
    _readyOk = _mode == EngineMode.linuxSubprocess
        ? (_process != null)
        : _mode == EngineMode.androidChaquopy;
    debugPrint('[DownloadEngine] Ready=$_readyOk mode=$_mode');
    if (!_ready.isCompleted) _ready.complete(_readyOk);
    return _readyOk;
  }

  Future<void> _initLinux() async {
    final docs = await getApplicationDocumentsDirectory();
    _appDataDir = '${docs.path}/fnb_data';
    await Directory(_appDataDir).create(recursive: true);

    // PyInstaller 打包的独立二进制（唯一路径）
    _pythonExe = '${Directory.current.path}/linux/python_bundle/bin/fnb_engine';
    if (!await File(_pythonExe).exists()) {
      debugPrint('[DownloadEngine] fnb_engine not found at $_pythonExe');
      _pythonExe = '';
      return;
    }

    debugPrint('[DownloadEngine] Starting bundle: $_pythonExe $_appDataDir');
    final proc = await Process.start(_pythonExe, [_appDataDir]);
    _attachProcess(proc);
  }

  void _attachProcess(Process proc) {
    _process = proc;
    proc.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      _stderrLog.add(line);
      if (_stderrLog.length > 200) _stderrLog.removeAt(0);
      debugPrint('[fnb] $line');
    });
    proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      line = line.trim();
      if (line.isEmpty) return;
      if (!line.startsWith('{') && !line.startsWith('[')) {
        debugPrint('[fnb-stdout-nonjson] $line');
        return;
      }
      final c = _responseCompleter;
      if (c != null && !c.isCompleted) {
        _responseCompleter = null;
        c.complete(line);
      } else {
        debugPrint('[fnb-stdout-orphan] $line');
      }
    });
    proc.exitCode.then((code) {
      debugPrint('[DownloadEngine] Subprocess exited: code=$code');
      _process = null;
      final c = _responseCompleter;
      if (c != null && !c.isCompleted) {
        c.complete(
            '{"success": false, "message": "Python process exited (code=$code)"}');
      }
    });
    _responseCompleter = Completer<String>();
    _responseCompleter!.future.then((line) {
      try {
        final r = jsonDecode(line);
        debugPrint('[DownloadEngine] Subprocess handshake: $r');
      } catch (_) {
        debugPrint('[DownloadEngine] Subprocess handshake (raw): $line');
      }
    });
  }

  Future<Map<String, dynamic>> _callSubprocess(
      String function, Map<String, dynamic> args,
      {Duration? timeout}) async {
    if (_process == null) {
      return {'success': false, 'message': 'Python subprocess not running'};
    }
    _responseCompleter = Completer<String>();
    final request = jsonEncode({'function': function, 'args': args});
    _process!.stdin.writeln(request);
    try {
      final line = await _responseCompleter!.future.timeout(
        timeout ?? const Duration(seconds: 60),
        onTimeout: () {
          _responseCompleter = null;
          return '{"success": false, "message": "Python subprocess timeout"}';
        },
      );
      return Map<String, dynamic>.from(jsonDecode(line) as Map);
    } catch (e) {
      return {
        'success': false,
        'message': 'Subprocess response parse error: $e'
      };
    }
  }

  Future<void> _initAndroid() async {
    final docs = await getApplicationDocumentsDirectory();
    _appDataDir = docs.path;
    try {
      final available = await _channel.invokeMethod<bool>('isAvailable');
      if (available != true) {
        debugPrint('[DownloadEngine] Chaquopy not available');
        return;
      }
      await _channel.invokeMethod('callBridge', {
        'function': 'init',
        'args': {'app_data_dir': _appDataDir},
      });
    } catch (e) {
      debugPrint('[DownloadEngine] Android init error: $e');
    }
  }

  Future<Map<String, dynamic>> call(String function, Map<String, dynamic> args,
      {Duration? timeout}) async {
    await initialize();
    switch (_mode) {
      case EngineMode.linuxSubprocess:
        return _callSubprocess(function, args, timeout: timeout);
      case EngineMode.androidChaquopy:
        try {
          final r = await _channel.invokeMethod<dynamic>('callBridge', {
            'function': function,
            'args': args,
          });
          if (r is Map) return Map<String, dynamic>.from(r);
          if (r is String) return Map<String, dynamic>.from(jsonDecode(r));
          return {'success': false, 'message': 'Unexpected result: $r'};
        } on PlatformException catch (e) {
          return {'success': false, 'message': e.message ?? e.code};
        }
      default:
        return {'success': false, 'message': '引擎不可用 ($_mode)'};
    }
  }

  Future<Map<String, dynamic>> callInBackground(
      String function, Map<String, dynamic> args) async {
    return call(function, args);
  }

  String newTaskId() => _uuid.v4();

  Future<Map<String, Map<String, dynamic>>> pollProgress() async {
    try {
      switch (_mode) {
        case EngineMode.linuxSubprocess:
          final file = File('$_appDataDir/fnb_progress.json');
          if (!await file.exists()) return {};
          final data = jsonDecode(await file.readAsString());
          if (data is Map) {
            return data.map((k, v) => MapEntry(k.toString(),
                v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{}));
          }
          return {};
        case EngineMode.androidChaquopy:
          final r = await call('get_progress', {});
          final p = r['progress'];
          if (p is Map) {
            return p.map((k, v) => MapEntry(k.toString(),
                v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{}));
          }
          return {};
        default:
          return {};
      }
    } catch (_) {
      return {};
    }
  }

  Future<void> pauseTask(String taskId) async {
    await call('pause_task', {'task_id': taskId});
  }

  Future<void> resumeTask(String taskId) async {
    await call('resume_task', {'task_id': taskId});
  }

  Future<Map<String, dynamic>> getStatus() async {
    switch (_mode) {
      case EngineMode.linuxSubprocess:
        return {
          'available': _process != null,
          'mode': 'linux-subprocess',
          'python': _pythonExe,
        };
      case EngineMode.androidChaquopy:
        try {
          final r = await call('status', {});
          r['mode'] = 'android-chaquopy';
          return r;
        } catch (e) {
          return {'available': false, 'error': e.toString()};
        }
      default:
        return {'available': false, 'mode': 'unsupported'};
    }
  }

  void dispose() {
    _process?.stdin.close();
    _process?.kill(ProcessSignal.sigterm);
    _process = null;
  }
}

enum EngineMode { linuxSubprocess, androidChaquopy, unsupported }
