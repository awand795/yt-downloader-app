import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

/// Raised for anything the native yt-dlp engine reports.
class EngineException implements Exception {
  EngineException(this.message, {this.code});

  final String message;
  final String? code;

  bool get isCancelled => code == 'CANCELLED';

  @override
  String toString() => message;
}

class EngineStatus {
  const EngineStatus({
    required this.version,
    required this.update,
    this.ready = false,
  });

  final String version;
  final String update;
  final bool ready;
}

class EngineProgress {
  const EngineProgress({
    required this.taskId,
    required this.fraction,
    required this.etaSeconds,
    required this.line,
  });

  final String taskId;

  /// 0..1 for the stream currently being fetched.
  final double fraction;
  final int etaSeconds;
  final String line;
}

/// Thin wrapper around the Kotlin channel that hosts yt-dlp on device.
class YtEngine {
  YtEngine._();

  static final YtEngine instance = YtEngine._();

  static const MethodChannel _channel = MethodChannel('tubegrab/engine');
  static const EventChannel _events = EventChannel('tubegrab/progress');

  Stream<EngineProgress>? _progressStream;

  Stream<EngineProgress> get progress {
    return _progressStream ??= _events.receiveBroadcastStream().map((event) {
      final map = (event as Map).cast<Object?, Object?>();
      return EngineProgress(
        taskId: (map['taskId'] as String?) ?? '',
        fraction: ((map['progress'] as num?)?.toDouble() ?? 0) / 100,
        etaSeconds: (map['eta'] as num?)?.toInt() ?? 0,
        line: (map['line'] as String?) ?? '',
      );
    });
  }

  Future<EngineStatus> init() async {
    final result = await _invoke<Map<Object?, Object?>>('init');
    return _status(result);
  }

  Future<EngineStatus> info() async {
    final result = await _invoke<Map<Object?, Object?>>('engineInfo');
    return _status(result);
  }

  Future<EngineStatus> update() async {
    final result = await _invoke<Map<Object?, Object?>>('updateEngine');
    return _status(result);
  }

  EngineStatus _status(Map<Object?, Object?>? map) {
    final version = (map?['version'] as String?) ?? '';
    return EngineStatus(
      version: version,
      update: (map?['update'] as String?) ?? '',
      ready: (map?['ready'] as bool?) ??
          (version.isNotEmpty && version != 'tidak diketahui'),
    );
  }

  Future<String> workDir() async {
    final dir = await _invoke<String>('workDir');
    return dir ?? '';
  }

  Future<Map<String, dynamic>> analyze(String url) async {
    final raw = await _invoke<String>('analyze', {'url': url});
    if (raw == null || raw.isEmpty) {
      throw EngineException('YouTube tidak mengembalikan data untuk tautan ini.');
    }
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw EngineException('Format data tidak dikenali.');
    }
    final decoded = jsonDecode(raw.substring(start, end + 1));
    if (decoded is! Map<String, dynamic>) {
      throw EngineException('Format data tidak dikenali.');
    }
    return decoded;
  }

  Future<String> download({
    required String url,
    required List<String> args,
    required String taskId,
  }) async {
    final path = await _invoke<String>('download', {
      'url': url,
      'args': args,
      'taskId': taskId,
      'template': '%(title).100B [%(id)s].%(ext)s',
    });
    if (path == null || path.isEmpty) {
      throw EngineException('Unduhan selesai tanpa menghasilkan berkas.');
    }
    return path;
  }

  Future<bool> cancel(String taskId) async {
    final result = await _invoke<bool>('cancel', {'taskId': taskId});
    return result ?? false;
  }

  Future<int> fileSize(String path) async {
    final size = await _invoke<int>('fileSize', {'path': path});
    return size ?? 0;
  }

  Future<String> saveToDownloads({
    required String path,
    required String name,
    required String mime,
  }) async {
    final result = await _invoke<String>('saveToDownloads', {
      'path': path,
      'name': name,
      'mime': mime,
    });
    if (result == null || result.isEmpty) {
      throw EngineException('Gagal menyimpan berkas ke folder Download.');
    }
    return result;
  }

  Future<bool> requestStoragePermission() async {
    final result = await _invoke<bool>('requestStoragePermission');
    return result ?? false;
  }

  Future<void> open(String locator, String mime) async {
    await _invoke<bool>('openFile', {'locator': locator, 'mime': mime});
  }

  Future<void> share(String locator, String mime) async {
    await _invoke<bool>('shareFile', {'locator': locator, 'mime': mime});
  }

  Future<bool> delete(String locator) async {
    final result = await _invoke<bool>('deleteFile', {'locator': locator});
    return result ?? false;
  }

  Future<Map<String, dynamic>> cookiesStatus() async {
    final result = await _invoke<Map<Object?, Object?>>('cookiesStatus');
    return (result ?? const {}).cast<String, dynamic>();
  }

  Future<String?> saveCookies(String content) async {
    return _invoke<String>('saveCookies', {'content': content});
  }

  Future<bool> clearCookies() async {
    final result = await _invoke<bool>('clearCookies');
    return result ?? false;
  }

  /// Opens the system file picker and imports a Netscape cookies.txt file.
  /// Returns the stored path, or null if the user cancelled.
  Future<String?> pickCookiesFile() async {
    return _invoke<String>('pickCookiesFile');
  }

  Future<T?> _invoke<T>(String method, [Map<String, dynamic>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (error) {
      throw EngineException(
        error.message ?? 'Mesin unduhan gagal memproses permintaan.',
        code: error.code,
      );
    } on MissingPluginException {
      throw EngineException(
        'Mesin unduhan hanya tersedia di Android.',
        code: 'UNSUPPORTED',
      );
    }
  }
}
