import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yt_downloader/core/theme.dart';
import 'package:yt_downloader/models/video_info.dart';
import 'package:yt_downloader/screens/result_screen.dart';

final _info = VideoInfo.fromJson({
  'id': 'abc123def45',
  'title': 'Video Uji dengan Judul Cukup Panjang untuk Menguji Pembungkusan Teks',
  'webpage_url': 'https://www.youtube.com/watch?v=abc123def45',
  'uploader': 'Kanal Uji',
  'thumbnail': '',
  'duration': 600,
  'view_count': 1500000,
  'upload_date': '20260115',
  'formats': [
    {'format_id': '137', 'ext': 'mp4', 'vcodec': 'avc1.640028', 'acodec': 'none', 'height': 1080, 'fps': 30, 'tbr': 4500, 'filesize': 100000000, 'protocol': 'https'},
    {'format_id': '136', 'ext': 'mp4', 'vcodec': 'avc1.4d401f', 'acodec': 'none', 'height': 720, 'tbr': 2000, 'filesize': 40000000, 'protocol': 'https'},
    {'format_id': '140', 'ext': 'm4a', 'vcodec': 'none', 'acodec': 'mp4a.40.2', 'abr': 128, 'filesize': 9000000, 'protocol': 'https'},
  ],
});

void main() {
  testWidgets('shows video+audio qualities by default and switches mode', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: ResultScreen(info: _info)),
    );
    await tester.pump();

    expect(find.text('Video + Audio'), findsOneWidget);
    expect(find.text('1080'), findsOneWidget);
    expect(find.text('Full HD · Terbaik'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Audio saja'));
    await tester.pump();

    expect(find.text('M4A (asli)'), findsOneWidget);
    expect(find.text('MP3 320 kbps'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Video saja'));
    await tester.pump();

    expect(find.text('tanpa audio'), findsNothing); // part of the subtitle
    expect(find.textContaining('tanpa audio'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
