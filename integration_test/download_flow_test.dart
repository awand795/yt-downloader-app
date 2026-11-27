import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yt_downloader/models/download_item.dart';
import 'package:yt_downloader/models/download_options.dart';
import 'package:yt_downloader/models/video_info.dart';
import 'package:yt_downloader/services/download_manager.dart';
import 'package:yt_downloader/services/engine.dart';

/// End-to-end check of the real yt-dlp engine on a device/emulator.
///
/// Run with: `flutter test integration_test/download_flow_test.dart -d <device>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const url = 'https://youtu.be/0wemf5SZkW4';

  test('engine analyzes a live video', () async {
    final status = await YtEngine.instance.init();
    expect(status.ready, isTrue, reason: 'yt-dlp tidak terpasang');
    // ignore: avoid_print
    print('engine: ${status.version} (${status.update})');

    final info = VideoInfo.fromJson(await YtEngine.instance.analyze(url));
    // ignore: avoid_print
    print('video: ${info.title} · ${info.duration} · ${info.formats.length} formats');
    expect(info.title, isNotEmpty);
    expect(info.formats.where((f) => f.hasVideo), isNotEmpty);
    expect(info.formats.where((f) => f.hasAudio), isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 6)));

  test('downloads audio only and publishes it to Downloads', () async {
    final info = VideoInfo.fromJson(await YtEngine.instance.analyze(url));
    final option = buildDownloadOptions(info, DownloadKind.audioOnly).first;

    await DownloadManager.instance.start(info: info, option: option);
    final task = DownloadManager.instance.active!;
    // ignore: avoid_print
    print('audio -> ${task.status} ${task.locator} (${task.bytes} bytes)');

    expect(task.status, TaskStatus.done, reason: task.error);
    expect(task.locator, isNotNull);
    expect(task.bytes, greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('downloads the smallest video+audio pair and merges it', () async {
    final info = VideoInfo.fromJson(await YtEngine.instance.analyze(url));
    final options = buildDownloadOptions(info, DownloadKind.videoAudio);
    final option = options.last; // lowest resolution keeps the test quick

    await DownloadManager.instance.start(info: info, option: option);
    final task = DownloadManager.instance.active!;
    // ignore: avoid_print
    print('video -> ${task.status} ${task.locator} (${task.bytes} bytes)');

    expect(task.status, TaskStatus.done, reason: task.error);
    expect(task.locator, isNotNull);
    expect(task.bytes, greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 12)));

  test('downloads a video without an audio track', () async {
    final info = VideoInfo.fromJson(await YtEngine.instance.analyze(url));
    final options = buildDownloadOptions(info, DownloadKind.videoOnly);
    final option = options.last;
    expect(option.merge, isFalse);
    expect(option.args[1].contains('+'), isFalse);

    await DownloadManager.instance.start(info: info, option: option);
    final task = DownloadManager.instance.active!;
    // ignore: avoid_print
    print('video-only -> ${task.status} ${task.locator} (${task.bytes} bytes)');

    expect(task.status, TaskStatus.done, reason: task.error);
    expect(task.locator, isNotNull);
  }, timeout: const Timeout(Duration(minutes: 12)));
}
