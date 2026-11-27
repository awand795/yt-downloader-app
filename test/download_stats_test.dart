import 'package:flutter_test/flutter_test.dart';
import 'package:yt_downloader/core/download_stats.dart';

void main() {
  test('parses a fragmented progress line with speed and an estimated size', () {
    final stats = parseDownloadStats(
      '[download]  45.2% of ~  1.80GiB at    2.10MiB/s ETA 00:12 (frag 42/300)',
    )!;

    expect(stats.totalBytes, closeTo(1.80 * 1024 * 1024 * 1024, 1024));
    expect(stats.speedBytesPerSecond, closeTo(2.10 * 1024 * 1024, 1024));
    expect(
      stats.downloadedBytes,
      closeTo(1.80 * 1024 * 1024 * 1024 * 0.452, 1024 * 1024),
    );
  });

  test('parses the final summary line', () {
    final stats = parseDownloadStats(
      '[download] 100% of   48.32MiB in 00:00:10 at 4.80MiB/s',
    )!;

    expect(stats.totalBytes, closeTo(48.32 * 1024 * 1024, 1));
    expect(stats.speedBytesPerSecond, closeTo(4.80 * 1024 * 1024, 1024));
  });

  test('keeps the size when the speed is unknown', () {
    final stats = parseDownloadStats(
      '[download]   0.0% of   10.00MiB at  Unknown B/s ETA Unknown',
    )!;

    expect(stats.totalBytes, 10 * 1024 * 1024);
    expect(stats.speedBytesPerSecond, isNull);
    expect(stats.downloadedBytes, 0);
  });

  test('ignores lines that are not download progress', () {
    expect(parseDownloadStats('[youtube] Extracting URL: https://youtu.be/x'), isNull);
    expect(parseDownloadStats('[Merger] Merging formats into "out.mp4"'), isNull);
  });
}
