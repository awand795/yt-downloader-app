import 'dart:math' as math;

/// Human friendly helpers shared across the UI.
String formatBytes(int? bytes, {int decimals = 1}) {
  if (bytes == null || bytes <= 0) return '—';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  final digits = size >= 100 || unit == 0 ? 0 : decimals;
  return '${size.toStringAsFixed(digits)} ${units[unit]}';
}

String formatDuration(Duration? duration) {
  if (duration == null || duration.inSeconds <= 0) return '—';
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  final mm = minutes.toString().padLeft(hours > 0 ? 2 : 1, '0');
  final ss = seconds.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}

String formatEta(int seconds) {
  if (seconds <= 0) return '';
  if (seconds < 60) return '$seconds dtk';
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  if (minutes < 60) return '$minutes mnt ${rest.toString().padLeft(2, '0')} dtk';
  final hours = minutes ~/ 60;
  return '$hours jam ${(minutes % 60).toString().padLeft(2, '0')} mnt';
}

String formatCompactCount(int? count) {
  if (count == null || count <= 0) return '';
  if (count >= 1000000000) return '${(count / 1000000000).toStringAsFixed(1)} M tayangan';
  if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)} jt tayangan';
  if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)} rb tayangan';
  return '$count tayangan';
}

String formatUploadDate(DateTime? date) {
  if (date == null) return '';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

/// Keeps a guessed size readable when only a bitrate is known.
int? estimateAudioBytes({required int? bitrateKbps, required Duration? duration}) {
  if (bitrateKbps == null || duration == null || duration.inSeconds <= 0) return null;
  final bytes = bitrateKbps * 1000 / 8 * duration.inSeconds;
  return math.max(bytes.round(), 0);
}
