/// Parsed view of a single yt-dlp JSON dump (`--dump-single-json`).
class VideoInfo {
  const VideoInfo({
    required this.id,
    required this.title,
    required this.url,
    required this.uploader,
    required this.thumbnail,
    required this.duration,
    required this.viewCount,
    required this.uploadedAt,
    required this.formats,
    required this.description,
  });

  final String id;
  final String title;
  final String url;
  final String uploader;
  final String thumbnail;
  final Duration? duration;
  final int? viewCount;
  final DateTime? uploadedAt;
  final List<MediaFormat> formats;
  final String description;

  factory VideoInfo.fromJson(Map<String, dynamic> json) {
    final rawFormats = (json['formats'] as List?) ?? const [];
    final formats = rawFormats
        .whereType<Map>()
        .map((f) => MediaFormat.fromJson(f.cast<String, dynamic>()))
        .where((f) => f.isUsable)
        .toList();

    return VideoInfo(
      id: (json['id'] as String?) ?? '',
      title: (json['title'] as String?)?.trim().isNotEmpty == true
          ? json['title'] as String
          : 'Video tanpa judul',
      url: (json['webpage_url'] as String?) ?? '',
      uploader: (json['uploader'] as String?) ??
          (json['channel'] as String?) ??
          'Tidak diketahui',
      thumbnail: (json['thumbnail'] as String?) ?? '',
      duration: _parseDuration(json['duration']),
      viewCount: (json['view_count'] as num?)?.toInt(),
      uploadedAt: _parseDate(json['upload_date'] as String?),
      formats: formats,
      description: (json['description'] as String?) ?? '',
    );
  }

  bool get hasVideo => formats.any((f) => f.hasVideo);
  bool get hasAudio => formats.any((f) => f.hasAudio);

  static Duration? _parseDuration(Object? value) {
    if (value is num) return Duration(seconds: value.round());
    if (value is String) {
      final seconds = double.tryParse(value);
      if (seconds != null) return Duration(seconds: seconds.round());
    }
    return null;
  }

  static DateTime? _parseDate(String? value) {
    if (value == null || value.length != 8) return null;
    final year = int.tryParse(value.substring(0, 4));
    final month = int.tryParse(value.substring(4, 6));
    final day = int.tryParse(value.substring(6, 8));
    if (year == null || month == null || day == null) return null;
    return DateTime(year, month, day);
  }
}

/// One entry from yt-dlp's `formats` array.
class MediaFormat {
  const MediaFormat({
    required this.id,
    required this.ext,
    required this.vcodec,
    required this.acodec,
    required this.height,
    required this.fps,
    required this.bytes,
    required this.bitrateKbps,
    required this.audioBitrateKbps,
    required this.note,
    required this.protocol,
  });

  final String id;
  final String ext;
  final String vcodec;
  final String acodec;
  final int? height;
  final int? fps;
  final int? bytes;
  final int? bitrateKbps;
  final int? audioBitrateKbps;
  final String note;
  final String protocol;

  factory MediaFormat.fromJson(Map<String, dynamic> json) {
    final filesize = (json['filesize'] as num?)?.toInt() ??
        (json['filesize_approx'] as num?)?.toInt();
    return MediaFormat(
      id: (json['format_id'] as String?) ?? '',
      ext: (json['ext'] as String?) ?? '',
      vcodec: (json['vcodec'] as String?) ?? 'none',
      acodec: (json['acodec'] as String?) ?? 'none',
      height: (json['height'] as num?)?.toInt(),
      fps: (json['fps'] as num?)?.round(),
      bytes: (filesize != null && filesize > 0) ? filesize : null,
      bitrateKbps: (json['tbr'] as num?)?.round(),
      audioBitrateKbps: (json['abr'] as num?)?.round(),
      note: (json['format_note'] as String?) ?? '',
      protocol: (json['protocol'] as String?) ?? '',
    );
  }

  bool get hasVideo => vcodec.isNotEmpty && vcodec != 'none';
  bool get hasAudio => acodec.isNotEmpty && acodec != 'none';

  /// Drops storyboard/manifest entries. Video entries must declare a height so
  /// the quality picker can group them; audio entries only need a codec.
  bool get isUsable {
    if (id.isEmpty) return false;
    if (protocol.startsWith('mhtml')) return false;
    if (hasVideo) return (height ?? 0) > 0;
    return hasAudio;
  }

  String get videoCodecName => codecLabel(vcodec);
  String get audioCodecName => codecLabel(acodec);

  static String codecLabel(String raw) {
    final codec = raw.toLowerCase();
    if (codec.startsWith('avc') || codec.contains('h264')) return 'H.264';
    if (codec.startsWith('hev') || codec.startsWith('hvc') || codec.contains('hevc')) {
      return 'HEVC';
    }
    if (codec.startsWith('av01') || codec.contains('av1')) return 'AV1';
    if (codec.startsWith('vp09') || codec.startsWith('vp9')) return 'VP9';
    if (codec.startsWith('vp8')) return 'VP8';
    if (codec.startsWith('mp4a') || codec.contains('aac')) return 'AAC';
    if (codec.contains('opus')) return 'Opus';
    if (codec.contains('vorbis')) return 'Vorbis';
    if (codec.contains('mp3')) return 'MP3';
    if (codec == 'none' || codec.isEmpty) return '—';
    return raw.toUpperCase();
  }
}
