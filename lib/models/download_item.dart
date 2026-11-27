import '../core/engine_activity.dart';
import 'download_options.dart';

enum TaskStatus { preparing, downloading, processing, saving, done, failed, canceled }

/// A download that is currently running (or just finished) in the manager.
class DownloadTask {
  DownloadTask({
    required this.id,
    required this.title,
    required this.uploader,
    required this.thumbnail,
    required this.label,
    required this.kind,
    required this.merge,
    required this.mime,
    required this.duration,
  });

  final String id;
  final String title;
  final String uploader;
  final String thumbnail;
  final String label;
  final DownloadKind kind;
  final bool merge;
  final String mime;
  final Duration? duration;

  TaskStatus status = TaskStatus.preparing;
  double fraction = 0;
  int etaSeconds = 0;
  double? speedBytesPerSecond;
  int? downloadedBytes;
  int? totalBytes;
  int bytes = 0;
  String? lastLine;
  final DateTime startedAt = DateTime.now();
  String? error;
  String? locator;
  int phase = 1;

  bool get isFinished =>
      status == TaskStatus.done ||
      status == TaskStatus.failed ||
      status == TaskStatus.canceled;

  /// Two-stream downloads are counted as video (first half) + audio (second).
  double get overallProgress {
    if (status == TaskStatus.done) return 1;
    if (!merge) return fraction.clamp(0, 1);
    final value = ((phase - 1) + fraction.clamp(0, 1)) / 2;
    return value.clamp(0, 1);
  }

  /// Human readable description of the current yt-dlp activity, e.g.
  /// "Menggabungkan video dan audio…". Null once nothing useful is known.
  String? get activity {
    final line = lastLine;
    if (line == null) return null;
    return describeEngineLine(line);
  }

  String get statusLabel {
    switch (status) {
      case TaskStatus.preparing:
        return 'Menyiapkan unduhan…';
      case TaskStatus.downloading:
        if (kind == DownloadKind.audioOnly) return 'Mengunduh audio…';
        if (merge && phase >= 2) return 'Mengunduh audio…';
        if (merge) return 'Mengunduh video…';
        return 'Mengunduh video…';
      case TaskStatus.processing:
        return merge ? 'Menggabungkan video & audio…' : 'Mengekstrak audio…';
      case TaskStatus.saving:
        return 'Menyimpan ke folder Download…';
      case TaskStatus.done:
        return locator != null && locator!.startsWith('content://')
            ? 'Tersimpan di Download/TubeGrab'
            : 'Tersimpan di penyimpanan aplikasi';
      case TaskStatus.failed:
        return error ?? 'Unduhan gagal';
      case TaskStatus.canceled:
        return 'Unduhan dibatalkan';
    }
  }
}

/// A finished download, persisted so it is still listed after a restart.
class HistoryItem {
  const HistoryItem({
    required this.id,
    required this.title,
    required this.uploader,
    required this.thumbnail,
    required this.label,
    required this.locator,
    required this.mime,
    required this.bytes,
    required this.savedAt,
    required this.duration,
  });

  final String id;
  final String title;
  final String uploader;
  final String thumbnail;
  final String label;
  final String locator;
  final String mime;
  final int bytes;
  final DateTime savedAt;
  final Duration? duration;

  bool get inPublicDownloads =>
      locator.startsWith('content://') || locator.contains('/Download/');

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'uploader': uploader,
        'thumbnail': thumbnail,
        'label': label,
        'locator': locator,
        'mime': mime,
        'bytes': bytes,
        'savedAt': savedAt.toIso8601String(),
        'duration': duration?.inSeconds,
      };

  factory HistoryItem.fromJson(Map<String, dynamic> json) {
    return HistoryItem(
      id: (json['id'] as String?) ?? '',
      title: (json['title'] as String?) ?? 'Video',
      uploader: (json['uploader'] as String?) ?? '',
      thumbnail: (json['thumbnail'] as String?) ?? '',
      label: (json['label'] as String?) ?? '',
      locator: (json['locator'] as String?) ?? '',
      mime: (json['mime'] as String?) ?? '*/*',
      bytes: (json['bytes'] as num?)?.toInt() ?? 0,
      savedAt: DateTime.tryParse((json['savedAt'] as String?) ?? '') ?? DateTime.now(),
      duration: (json['duration'] as num?) == null
          ? null
          : Duration(seconds: (json['duration'] as num).toInt()),
    );
  }
}
