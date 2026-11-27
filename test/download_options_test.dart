import 'package:flutter_test/flutter_test.dart';
import 'package:yt_downloader/models/download_options.dart';
import 'package:yt_downloader/models/video_info.dart';

const _json = {
  'id': 'abc123def45',
  'title': 'Contoh Video',
  'webpage_url': 'https://www.youtube.com/watch?v=abc123def45',
  'uploader': 'Kanal Uji',
  'thumbnail': 'https://i.ytimg.com/vi/abc123def45/maxresdefault.jpg',
  'duration': 600,
  'view_count': 1500000,
  'upload_date': '20260115',
  'formats': [
    {
      'format_id': '137',
      'ext': 'mp4',
      'vcodec': 'avc1.640028',
      'acodec': 'none',
      'height': 1080,
      'fps': 30,
      'tbr': 4500,
      'filesize': 100000000,
      'protocol': 'https',
    },
    {
      'format_id': '399',
      'ext': 'mp4',
      'vcodec': 'av01.0.08M.08',
      'acodec': 'none',
      'height': 1080,
      'tbr': 5000,
      'filesize': 80000000,
      'protocol': 'https',
    },
    {
      'format_id': '248',
      'ext': 'webm',
      'vcodec': 'vp9',
      'acodec': 'none',
      'height': 1080,
      'tbr': 4000,
      'filesize': 70000000,
      'protocol': 'https',
    },
    {
      'format_id': '136',
      'ext': 'mp4',
      'vcodec': 'avc1.4d401f',
      'acodec': 'none',
      'height': 720,
      'tbr': 2000,
      'filesize': 40000000,
      'protocol': 'https',
    },
    {
      'format_id': '140',
      'ext': 'm4a',
      'vcodec': 'none',
      'acodec': 'mp4a.40.2',
      'abr': 128,
      'filesize': 9000000,
      'protocol': 'https',
    },
    {
      'format_id': '251',
      'ext': 'webm',
      'vcodec': 'none',
      'acodec': 'opus',
      'abr': 160,
      'filesize': 11000000,
      'protocol': 'https',
    },
    {
      'format_id': '18',
      'ext': 'mp4',
      'vcodec': 'avc1.42001E',
      'acodec': 'mp4a.40.2',
      'height': 360,
      'tbr': 600,
      'protocol': 'https',
    },
    {
      'format_id': 'sb0',
      'ext': 'mhtml',
      'vcodec': 'none',
      'acodec': 'none',
      'protocol': 'mhtml',
    },
  ],
};

void main() {
  final info = VideoInfo.fromJson(Map<String, dynamic>.from(_json));

  test('parses video metadata and drops storyboard formats', () {
    expect(info.title, 'Contoh Video');
    expect(info.duration, const Duration(minutes: 10));
    expect(info.viewCount, 1500000);
    expect(info.uploadedAt, DateTime(2026, 1, 15));
    expect(info.formats.any((f) => f.protocol == 'mhtml'), isFalse);
    expect(info.formats.length, 7);
  });

  test('video + audio options are grouped by resolution, highest first', () {
    final options = buildDownloadOptions(info, DownloadKind.videoAudio);
    expect(options.map((o) => o.title), ['1080', '720', '360']);
    // H.264 is preferred over AV1/VP9 at the same height for compatibility, and
    // the selector uses attributes instead of per-session format ids.
    expect(options.first.args[1], contains('height=1080'));
    expect(options.first.args[1], contains('vcodec^=avc1'));
    expect(options.first.args, containsAll(['--merge-output-format', 'mp4']));
    expect(options.first.container, 'MP4');
    expect(options.first.merge, isTrue);
    expect(options.first.bytes, 109000000);

    // Without an H.264 stream the fallback branches keep the mp4 container.
    final vp9Only = VideoInfo.fromJson({
      ..._json,
      'formats': [
        {
          'format_id': '248',
          'ext': 'webm',
          'vcodec': 'vp9',
          'acodec': 'none',
          'height': 1080,
          'protocol': 'https',
        },
        {
          'format_id': '251',
          'ext': 'webm',
          'vcodec': 'none',
          'acodec': 'opus',
          'protocol': 'https',
        },
      ],
    });
    final vp9Options = buildDownloadOptions(vp9Only, DownloadKind.videoAudio);
    expect(vp9Options.single.container, 'MP4');
    expect(vp9Options.single.args[1], contains('/bv*[height=1080]+ba'));
  });

  test('video-only options never merge audio', () {
    final options = buildDownloadOptions(info, DownloadKind.videoOnly);
    expect(options, isNotEmpty);
    for (final option in options) {
      expect(option.merge, isFalse);
      expect(option.args[1].contains('+'), isFalse);
      expect(option.args, containsAll(['--remux-video', 'mp4']));
    }
    expect(options.first.args[1], contains('bv*[height=1080]'));
  });

  test('audio options offer native m4a plus mp3 bitrates', () {
    final options = buildDownloadOptions(info, DownloadKind.audioOnly);
    expect(options.map((o) => o.title),
        ['M4A (asli)', 'MP3 320 kbps', 'MP3 192 kbps', 'MP3 128 kbps']);
    expect(options.first.ext, 'm4a');
    expect(options[1].args, containsAll(['-x', '--audio-format', 'mp3', '320K']));
    // 320 kbps * 600s / 8 = 24 MB
    expect(options[1].bytes, 24000000);
  });

  test('default option caps at 1080p', () {
    final options = buildDownloadOptions(info, DownloadKind.videoAudio);
    expect(defaultOption(options, DownloadKind.videoAudio)?.title, '1080');
  });
}
