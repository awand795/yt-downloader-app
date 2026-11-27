import '../core/formatters.dart';
import 'video_info.dart';

/// What the user wants out of a link.
enum DownloadKind {
  videoAudio('Video + Audio', 'Terkunci'),
  videoOnly('Video saja', 'Tanpa suara'),
  audioOnly('Audio saja', 'M4A / MP3');

  const DownloadKind(this.label, this.hint);

  final String label;
  final String hint;
}

/// One row in the quality list: a ready-to-run yt-dlp argument set.
class DownloadOption {
  const DownloadOption({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.container,
    required this.args,
    required this.ext,
    required this.mime,
    required this.bytes,
    required this.merge,
  });

  final DownloadKind kind;

  /// e.g. `1080p`, `MP3 320 kbps`.
  final String title;

  /// e.g. `MP4 · H.264 · 30 fps`.
  final String subtitle;

  /// Short flag shown on the right, e.g. `Full HD`.
  final String badge;

  /// Container/ext label shown as a chip.
  final String container;

  /// yt-dlp arguments (already tokenised).
  final List<String> args;

  final String ext;
  final String mime;

  /// Rough output size, when yt-dlp reported one.
  final int? bytes;

  /// Video + audio merged from two streams (needs the ffmpeg phase).
  final bool merge;

  String get sizeLabel => bytes == null ? 'Ukuran tidak diketahui' : '± ${formatBytes(bytes)}';
}

const _videoQoSLabels = {
  4320: '8K',
  2160: '4K',
  1440: '2K',
  1080: 'Full HD',
  720: 'HD',
  480: 'SD',
  360: '360p',
  240: '240p',
  144: '144p',
};

List<DownloadOption> buildDownloadOptions(VideoInfo info, DownloadKind kind) {
  switch (kind) {
    case DownloadKind.videoAudio:
      return _videoOptions(info, withAudio: true);
    case DownloadKind.videoOnly:
      return _videoOptions(info, withAudio: false);
    case DownloadKind.audioOnly:
      return _audioOptions(info);
  }
}

// ---------------------------------------------------------------- video side

List<DownloadOption> _videoOptions(VideoInfo info, {required bool withAudio}) {
  final bestPerHeight = <int, MediaFormat>{};
  for (final format in info.formats.where((f) => f.hasVideo)) {
    final height = format.height ?? 0;
    if (height <= 0) continue;
    final current = bestPerHeight[height];
    if (current == null || _videoScore(format) > _videoScore(current)) {
      bestPerHeight[height] = format;
    }
  }
  if (bestPerHeight.isEmpty) return const [];

  final heights = bestPerHeight.keys.toList()..sort((a, b) => b.compareTo(a));
  final bestAudio = _bestAudio(info);
  final options = <DownloadOption>[];

  for (final height in heights) {
    final video = bestPerHeight[height]!;

    if (!withAudio || bestAudio == null) {
      options.add(
        DownloadOption(
          kind: withAudio ? DownloadKind.videoAudio : DownloadKind.videoOnly,
          title: '$height',
          subtitle: [
            'MP4',
            video.videoCodecName,
            if (video.fps != null && video.fps! > 30) '${video.fps} fps',
            'tanpa audio',
          ].join(' · '),
          badge: heights.first == height ? '${_videoQoSLabels[height] ?? ''} · Terbaik'.trim() : (_videoQoSLabels[height] ?? ''),
          container: 'MP4',
          // Attribute selectors survive YouTube's per-session format ids, which
          // change between the analyze call and the download call.
          args: [
            '-f',
            'bv*[height=$height][ext=mp4][vcodec^=avc1]/bv*[height=$height][ext=mp4]/bv*[height=$height]/b[height=$height]',
            '--remux-video',
            'mp4',
          ],
          ext: 'mp4',
          mime: 'video/mp4',
          bytes: video.bytes,
          merge: false,
        ),
      );
      continue;
    }

    final size = (video.bytes != null || bestAudio.bytes != null)
        ? (video.bytes ?? 0) + (bestAudio.bytes ?? 0)
        : null;

    options.add(
      DownloadOption(
        kind: DownloadKind.videoAudio,
        title: '$height',
        subtitle: [
          'MP4',
          video.videoCodecName,
          '${bestAudio.audioCodecName} ${bestAudio.audioBitrateKbps ?? '?'} kbps',
          if (video.fps != null && video.fps! > 30) '${video.fps} fps',
        ].join(' · '),
        badge: heights.first == height
            ? '${_videoQoSLabels[height] ?? ''} · Terbaik'.trim()
            : (_videoQoSLabels[height] ?? ''),
        container: 'MP4',
        args: [
          '-f',
          'bv*[height=$height][vcodec^=avc1]+ba[ext=m4a]'
              '/bv*[height=$height]+ba[ext=m4a]'
              '/bv*[height=$height]+ba'
              '/b[height=$height]',
          '--merge-output-format',
          'mp4',
        ],
        ext: 'mp4',
        mime: 'video/mp4',
        bytes: size,
        merge: true,
      ),
    );
  }

  return options;
}

int _videoScore(MediaFormat format) {
  var score = 0;
  // H.264/MP4 plays everywhere, including older TVs and WhatsApp previews.
  if (format.ext == 'mp4') score += 60;
  if (format.vcodec.toLowerCase().startsWith('avc')) score += 40;
  score += ((format.bitrateKbps ?? 0) / 100).round();
  return score;
}

MediaFormat? _bestAudio(VideoInfo info) {
  final audios = info.formats.where((f) => f.hasAudio && !f.hasVideo).toList();
  if (audios.isEmpty) return null;
  audios.sort((a, b) {
    final aScore = (a.ext == 'm4a' ? 1000 : 0) + (a.audioBitrateKbps ?? 0);
    final bScore = (b.ext == 'm4a' ? 1000 : 0) + (b.audioBitrateKbps ?? 0);
    return bScore.compareTo(aScore);
  });
  return audios.first;
}

// ---------------------------------------------------------------- audio side

List<DownloadOption> _audioOptions(VideoInfo info) {
  final audio = _bestAudio(info);
  final duration = info.duration;
  final sourceKbps = audio?.audioBitrateKbps ?? 128;

  DownloadOption mp3(int kbps) {
    final estimate = duration == null
        ? null
        : estimateAudioBytes(bitrateKbps: kbps, duration: duration);
    return DownloadOption(
      kind: DownloadKind.audioOnly,
      title: 'MP3 $kbps kbps',
      subtitle: 'MP3 · 44.1 kHz · kompatibel di semua pemutar',
      badge: '',
      container: 'MP3',
      args: [
        '-f',
        'bestaudio/best',
        '-x',
        '--audio-format',
        'mp3',
        '--audio-quality',
        '${kbps}K',
      ],
      ext: 'mp3',
      mime: 'audio/mpeg',
      bytes: estimate,
      merge: false,
    );
  }

  return [
    DownloadOption(
      kind: DownloadKind.audioOnly,
      title: 'M4A (asli)',
      subtitle: 'M4A · AAC $sourceKbps kbps · tanpa konversi',
      badge: 'Terbaik',
      container: 'M4A',
      args: ['-f', 'bestaudio[ext=m4a]/bestaudio', '-x', '--audio-format', 'm4a'],
      ext: 'm4a',
      mime: 'audio/mp4',
      bytes: audio?.bytes ??
          estimateAudioBytes(bitrateKbps: sourceKbps, duration: duration),
      merge: false,
    ),
    mp3(320),
    mp3(192),
    mp3(128),
  ];
}

/// The row that should be pre-selected when a sheet opens: the best video up to
/// 1080p (the practical limit of most phones) or highest audio quality.
DownloadOption? defaultOption(List<DownloadOption> options, DownloadKind kind) {
  if (options.isEmpty) return null;
  if (kind != DownloadKind.videoAudio && kind != DownloadKind.videoOnly) {
    return options.first;
  }
  if (kind == DownloadKind.videoOnly) return options.first;
  for (final option in options) {
    final height = int.tryParse(option.title);
    if (height != null && height <= 1080) return option;
  }
  return options.first;
}
