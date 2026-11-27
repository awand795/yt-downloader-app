/// Turns the raw yt-dlp output lines the native engine streams back into a
/// short Indonesian description of what the download is doing right now.
///
/// The engine reports lines such as
/// `[youtube] Extracting URL: https://…` or `[Merger] Merging formats into …`.
/// Those are precise but unreadable for most users, so the UI shows the mapped
/// sentence instead. Returns null when the line carries no useful information.
String? describeEngineLine(String line) {
  final text = line.trim();
  if (text.isEmpty) return null;

  for (final rule in _rules) {
    if (rule.pattern.hasMatch(text)) return rule.label;
  }
  return null;
}

class _ActivityRule {
  const _ActivityRule(this.pattern, this.label);

  final RegExp pattern;
  final String label;
}

final List<_ActivityRule> _rules = [
  // ------------------------------------------------------------- extraction
  _ActivityRule(
    RegExp(r'\[youtube\]\s+extracting url|downloading webpage|^\[youtube\]\s+\S+$',
        caseSensitive: false),
    'Membuka halaman video YouTube…',
  ),
  _ActivityRule(
    RegExp(r'player|client config|api json', caseSensitive: false),
    'Menyiapkan sesi pemutar YouTube…',
  ),
  _ActivityRule(
    RegExp(r'downloading (webpage|initial data|chapters|comments)', caseSensitive: false),
    'Mengambil info video…',
  ),
  _ActivityRule(
    RegExp(r'downloading (m3u8|mpd|manifest)', caseSensitive: false),
    'Membaca daftar segmen video…',
  ),
  _ActivityRule(
    RegExp(r'extracting url|downloading api page|login', caseSensitive: false),
    'Membaca alamat video…',
  ),

  // --------------------------------------------------------------- download
  _ActivityRule(
    RegExp(r'\[info\].*downloading \d+ format|downloading format\(s\)',
        caseSensitive: false),
    'Memilih berkas video dan audio…',
  ),
  _ActivityRule(
    RegExp(r'\[download\]\s+destination', caseSensitive: false),
    'Membuka koneksi ke server YouTube…',
  ),
  _ActivityRule(
    RegExp(r'frag\s+\d+|\bfragments?\b|\[dashsegments\]|\[hlsnative\]',
        caseSensitive: false),
    'Mengunduh potongan video…',
  ),
  _ActivityRule(
    RegExp(r'^\[download\]\s+\d'),
    'Menerima data dari server YouTube…',
  ),

  // --------------------------------------------------------------- ffmpeg
  _ActivityRule(
    RegExp(r'\[merger\]|merging formats|\[ffmpeg\]\s+merging', caseSensitive: false),
    'Menggabungkan video dan audio…',
  ),
  _ActivityRule(
    RegExp(r'\[extractaudio\]|destination:\s.*\.(m4a|mp3|opus|flac|wav)$',
        caseSensitive: false),
    'Mengekstrak audio dengan FFmpeg…',
  ),
  _ActivityRule(
    RegExp(r'\[videoconvertor\]|\[videoremuxer\]|remux', caseSensitive: false),
    'Mengubah wadah video ke MP4…',
  ),
  _ActivityRule(
    RegExp(r'\[ffmpeg\]|\[fixup', caseSensitive: false),
    'Memproses berkas dengan FFmpeg…',
  ),
  _ActivityRule(
    RegExp(r'deleting original file|\[metadata\]|\[embedthumbnail\]|writing video metadata',
        caseSensitive: false),
    'Merapikan berkas hasil unduhan…',
  ),
];
