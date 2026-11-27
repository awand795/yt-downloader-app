import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/download_item.dart';
import '../models/download_options.dart';
import '../models/video_info.dart';
import 'engine.dart';

/// Owns the single active download plus the persisted history list.
class DownloadManager extends ChangeNotifier {
  DownloadManager._();

  static final DownloadManager instance = DownloadManager._();

  static const _historyKey = 'history_v1';

  DownloadTask? _active;
  List<HistoryItem> _history = const [];
  StreamSubscription<EngineProgress>? _subscription;
  bool _loaded = false;

  DownloadTask? get active => _active;
  List<HistoryItem> get history => _history;
  bool get isBusy => _active != null && !_active!.isFinished;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    _subscription ??= YtEngine.instance.progress.listen(_onProgress);

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _history = decoded
            .whereType<Map>()
            .map((map) => HistoryItem.fromJson(map.cast<String, dynamic>()))
            .where((item) => item.locator.isNotEmpty)
            .toList();
        notifyListeners();
      }
    } catch (_) {
      // Corrupted history should never block the app.
    }
  }

  void _onProgress(EngineProgress event) {
    final task = _active;
    if (task == null || task.id != event.taskId) return;

    if (task.merge && event.fraction + 0.05 < task.fraction && task.phase == 1) {
      task.phase = 2;
    }
    task.fraction = event.fraction.clamp(0, 1);
    task.etaSeconds = event.etaSeconds;
    if (event.line.trim().isNotEmpty) {
      task.lastLine = event.line.trim();
    }
    if (task.status != TaskStatus.saving && task.status != TaskStatus.done) {
      // Zero progress before the first byte keeps the card in "preparing";
      // it must never fall back to preparing once data has arrived.
      if (task.fraction > 0) {
        task.status = task.fraction >= 0.999
            ? TaskStatus.processing
            : TaskStatus.downloading;
      }
    }
    notifyListeners();
  }

  Future<void> start({
    required VideoInfo info,
    required DownloadOption option,
  }) async {
    if (isBusy) {
      throw EngineException('Masih ada unduhan yang berjalan. Selesaikan dulu ya.');
    }

    final task = DownloadTask(
      id: 'tg-${DateTime.now().microsecondsSinceEpoch}',
      title: info.title,
      uploader: info.uploader,
      thumbnail: info.thumbnail,
      label: '${option.title} · ${option.container}',
      kind: option.kind,
      merge: option.merge,
      mime: option.mime,
      duration: info.duration,
    );
    _active = task;
    notifyListeners();

    try {
      await YtEngine.instance.init();
      // Stay in "preparing" until yt-dlp reports real progress; the status
      // flips to "downloading" from _onProgress once bytes start moving.
      notifyListeners();
      final path = await YtEngine.instance.download(
        url: info.url,
        args: option.args,
        taskId: task.id,
      );

      task.status = TaskStatus.saving;
      notifyListeners();

      final bytes = await YtEngine.instance.fileSize(path);
      final locator = await _publish(path, option);

      task
        ..locator = locator
        ..bytes = bytes > 0 ? bytes : (option.bytes ?? 0)
        ..fraction = 1
        ..status = TaskStatus.done;

      _history = [
        HistoryItem(
          id: task.id,
          title: info.title,
          uploader: info.uploader,
          thumbnail: info.thumbnail,
          label: task.label,
          locator: locator,
          mime: option.mime,
          bytes: task.bytes,
          savedAt: DateTime.now(),
          duration: info.duration,
        ),
        ..._history,
      ];
      unawaited(_persist());
    } on EngineException catch (error) {
      task.status = error.isCancelled ? TaskStatus.canceled : TaskStatus.failed;
      task.error = error.isCancelled ? null : error.message;
    } catch (error) {
      task.status = TaskStatus.failed;
      task.error = error.toString();
    }
    notifyListeners();
  }

  /// Copies the finished file into Download/TubeGrab. Falls back to the app's
  /// own folder when the user denies a storage permission on old Androids.
  Future<String> _publish(String path, DownloadOption option) async {
    final name = path.split(RegExp(r'[\\/]')).last;
    try {
      return await YtEngine.instance.saveToDownloads(
        path: path,
        name: name,
        mime: option.mime,
      );
    } on EngineException catch (error) {
      if (error.code == 'PERMISSION_REQUIRED') {
        final granted = await YtEngine.instance.requestStoragePermission();
        if (granted) {
          return YtEngine.instance.saveToDownloads(
            path: path,
            name: name,
            mime: option.mime,
          );
        }
      }
      return path;
    }
  }

  Future<void> cancel() async {
    final task = _active;
    if (task == null || task.isFinished) return;
    await YtEngine.instance.cancel(task.id);
    task.status = TaskStatus.canceled;
    notifyListeners();
  }

  /// Clears a finished card from the home screen.
  void dismissActive() {
    if (_active == null) return;
    if (!_active!.isFinished) return;
    _active = null;
    notifyListeners();
  }

  Future<void> removeHistory(HistoryItem item) async {
    _history = _history.where((entry) => entry.id != item.id).toList();
    notifyListeners();
    try {
      await YtEngine.instance.delete(item.locator);
    } catch (_) {
      // The file may already be gone; the entry is removed either way.
    }
    await _persist();
  }

  Future<void> openHistory(HistoryItem item) =>
      YtEngine.instance.open(item.locator, item.mime);

  Future<void> shareHistory(HistoryItem item) =>
      YtEngine.instance.share(item.locator, item.mime);

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _historyKey,
      jsonEncode(_history.map((item) => item.toJson()).toList()),
    );
  }
}
