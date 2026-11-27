/// Speed and size numbers parsed from a yt-dlp `[download]` progress line,
/// e.g. `[download]  45.2% of    1.80GiB at    2.10MiB/s ETA 00:12`.
class DownloadStats {
  const DownloadStats({
    this.speedBytesPerSecond,
    this.downloadedBytes,
    this.totalBytes,
  });

  final double? speedBytesPerSecond;
  final int? downloadedBytes;
  final int? totalBytes;
}

final _percentPattern = RegExp(r'\[download\]\s+([\d.]+)%');
final _totalPattern = RegExp(r'\bof\s+~?\s*([\d.]+)\s*([KMGT]?i?B)\b');
final _speedPattern = RegExp(r'\bat\s+([\d.]+)\s*([KMGT]?i?B)/s');

DownloadStats? parseDownloadStats(String line) {
  if (!line.contains('[download]')) return null;

  final percent = double.tryParse(
    _percentPattern.firstMatch(line)?.group(1) ?? '',
  );
  final totalMatch = _totalPattern.firstMatch(line);
  final totalValue = double.tryParse(totalMatch?.group(1) ?? '');
  final total = (totalMatch != null && totalValue != null)
      ? _bytes(totalValue, totalMatch.group(2)!)
      : null;

  final speedMatch = _speedPattern.firstMatch(line);
  final speedValue = double.tryParse(speedMatch?.group(1) ?? '');
  final speed = (speedMatch != null && speedValue != null)
      ? _bytes(speedValue, speedMatch.group(2)!).toDouble()
      : null;

  final downloaded = (percent != null && total != null)
      ? (total * percent / 100).round()
      : null;
  if (downloaded == null && speed == null) return null;

  return DownloadStats(
    speedBytesPerSecond: speed,
    downloadedBytes: downloaded,
    totalBytes: total,
  );
}

int _bytes(double value, String unit) {
  final base = unit.contains('i') ? 1024 : 1000;
  final power = switch (unit[0]) {
    'K' => 1,
    'M' => 2,
    'G' => 3,
    'T' => 4,
    _ => 0,
  };
  var result = value;
  for (var i = 0; i < power; i++) {
    result *= base;
  }
  return result.round();
}
