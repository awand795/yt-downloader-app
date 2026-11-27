import 'package:flutter_test/flutter_test.dart';
import 'package:yt_downloader/core/engine_activity.dart';

void main() {
  test('maps raw yt-dlp lines to readable activity text', () {
    expect(
      describeEngineLine('[youtube] Extracting URL: https://youtu.be/abc'),
      'Membuka halaman video YouTube…',
    );
    expect(
      describeEngineLine('[info] abc123: Downloading 1 format(s): 137+140'),
      'Memilih berkas video dan audio…',
    );
    expect(
      describeEngineLine('[Merger] Merging formats into "out.mp4"'),
      'Menggabungkan video dan audio…',
    );
    expect(
      describeEngineLine(
        '[download]  12.3% of 100.00MiB at 1.00MiB/s ETA 00:12 (frag 2/10)',
      ),
      'Mengunduh potongan video…',
    );
    expect(
      describeEngineLine('[download]  12.3% of 100.00MiB at 1.00MiB/s ETA 00:12'),
      'Menerima data dari server YouTube…',
    );
    expect(describeEngineLine('   '), isNull);
  });
}
