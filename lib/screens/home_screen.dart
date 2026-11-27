import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/download_item.dart';
import '../models/video_info.dart';
import '../services/download_manager.dart';
import '../services/engine.dart';
import '../widgets/active_download_card.dart';
import '../widgets/history_tile.dart';
import 'result_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _controller = TextEditingController();
  final _manager = DownloadManager.instance;

  EngineStatus? _status;
  bool _preparing = true;
  bool _analyzing = false;
  String? _engineError;
  DateTime? _analyzeStartedAt;
  Timer? _analyzeTicker;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _prepareEngine();
  }

  @override
  void dispose() {
    _analyzeTicker?.cancel();
    _controller
      ..removeListener(_onTextChanged)
      ..dispose();
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  Future<void> _prepareEngine() async {
    setState(() {
      _preparing = true;
      _engineError = null;
    });
    try {
      final status = await YtEngine.instance.init();
      if (!mounted) return;
      setState(() {
        _status = status;
        _preparing = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _engineError = error.toString();
        _preparing = false;
      });
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String? _normalizeLink(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;
    if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(text)) {
      return 'https://www.youtube.com/watch?v=$text';
    }
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) return null;
    final host = uri.host.toLowerCase().replaceFirst('www.', '');
    const hosts = {
      'youtube.com',
      'm.youtube.com',
      'music.youtube.com',
      'youtu.be',
      'youtube-nocookie.com',
    };
    if (!hosts.contains(host)) return null;
    return text;
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      _toast('Clipboard kosong');
      return;
    }
    _controller
      ..text = text
      ..selection = TextSelection.collapsed(offset: text.length);
  }

  Future<void> _analyze() async {
    final link = _normalizeLink(_controller.text);
    if (link == null) {
      _toast('Tempel tautan video YouTube yang valid');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _analyzing = true;
      _analyzeStartedAt = DateTime.now();
    });
    // yt-dlp gives no progress while it reads the page, so tick a counter to
    // make the wait visible instead of a silent spinner.
    _analyzeTicker?.cancel();
    _analyzeTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    try {
      Map<String, dynamic> json;
      try {
        json = await YtEngine.instance.analyze(link);
      } on EngineException catch (error) {
        // The bundled yt-dlp is often too old; a stale engine commonly fails
        // with "The page needs to be reloaded" or 403. Try one automatic
        // update + retry before surfacing the error.
        final lower = error.message.toLowerCase();
        final retriable = lower.contains('page needs to be reloaded') ||
            lower.contains('unable to extract') ||
            lower.contains('403') ||
            lower.contains('forbidden');
        if (!retriable) rethrow;
        _toast('Memperbarui mesin yt-dlp…');
        try {
          await YtEngine.instance.update();
        } on EngineException catch (updateError) {
          throw EngineException(
            'Mesin yt-dlp gagal diperbarui. Periksa koneksi internet (sebaiknya Wi-Fi), '
            'lalu buka menu Mesin unduhan → Perbarui mesin sekarang.\n'
            '${updateError.message}',
            code: error.code,
          );
        }
        json = await YtEngine.instance.analyze(link);
      }
      final info = VideoInfo.fromJson(json);
      if (info.formats.isEmpty) {
        throw EngineException('Video ini tidak punya format yang bisa diunduh.');
      }
      _analyzeTicker?.cancel();
      if (!mounted) return;
      setState(() => _analyzing = false);
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => ResultScreen(info: info)),
      );
    } on EngineException catch (error) {
      _analyzeTicker?.cancel();
      if (!mounted) return;
      setState(() => _analyzing = false);
      final lower = error.message.toLowerCase();
      if (lower.contains('sign in to confirm') || lower.contains('not a bot')) {
        _toast('YouTube meminta verifikasi. Impor cookies di menu Mesin unduhan.');
      } else if (lower.contains('page needs to be reloaded')) {
        _toast('Mesin yt-dlp perlu diperbarui. Buka menu Mesin unduhan → Perbarui mesin sekarang, lalu coba lagi.');
      } else if (lower.contains('403') || lower.contains('forbidden')) {
        _toast('YouTube menolak akses (403). Coba perbarui mesin di menu Mesin unduhan.');
      } else {
        _toast(error.message);
      }
    } catch (error) {
      _analyzeTicker?.cancel();
      if (!mounted) return;
      setState(() => _analyzing = false);
      _toast('Gagal membaca video: $error');
    }
  }

  String get _analyzeLabel {
    final started = _analyzeStartedAt;
    if (!_analyzing || started == null) return 'Analisa tautan';
    final seconds = DateTime.now().difference(started).inSeconds;
    return seconds < 1 ? 'Menganalisa video…' : 'Menganalisa video… ${formatEta(seconds)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: _manager,
          builder: (context, _) {
            final task = _manager.active;
            final history = _manager.history;
            return CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                    child: _buildHeader(context),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
                    child: _buildLinkCard(context),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: _buildEngineBadge(context),
                  ),
                ),
                if (task != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                      child: ActiveDownloadCard(
                        task: task,
                        onCancel: _manager.cancel,
                        onDismiss: _manager.dismissActive,
                        onOpen: () => _openTask(task),
                        onShare: () => _shareTask(task),
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 26, 20, 12),
                    child: Row(
                      children: [
                        Text(
                          'Riwayat',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 16),
                        ),
                        const SizedBox(width: 8),
                        if (history.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceAlt,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.stroke),
                            ),
                            child: Text(
                              '${history.length}',
                              style: const TextStyle(fontSize: 10.5, color: AppColors.muted, fontWeight: FontWeight.w700),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (history.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _buildEmptyHistory(context),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverList.builder(
                      itemCount: history.length,
                      itemBuilder: (context, index) {
                        final item = history[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: HistoryTile(
                            item: item,
                            onOpen: () => _openItem(item),
                            onShare: () => _shareItem(item),
                            onDelete: () => _deleteItem(item),
                          ),
                        );
                      },
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(24, 0, 24, MediaQuery.paddingOf(context).bottom + 20),
                    child: Row(
                      children: [
                        const Icon(Icons.shield_outlined, size: 13, color: AppColors.faint),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Gunakan hanya untuk konten yang Anda miliki haknya. TubeGrab tidak berafiliasi dengan YouTube.',
                            style: TextStyle(fontSize: 10.5, height: 1.4, color: AppColors.faint),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.accent, AppColors.accentWarm],
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withValues(alpha: 0.35),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('TubeGrab', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 2),
            const Text(
              'YOUTUBE DOWNLOADER',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.8,
                color: AppColors.faint,
              ),
            ),
          ],
        ),
        const Spacer(),
        IconButton(
          onPressed: _showEngineSheet,
          icon: const Icon(Icons.tune_rounded, size: 20),
          color: AppColors.muted,
          style: IconButton.styleFrom(
            backgroundColor: AppColors.surface,
            side: const BorderSide(color: AppColors.stroke),
          ),
          tooltip: 'Mesin unduhan',
        ),
      ],
    );
  }

  Widget _buildLinkCard(BuildContext context) {
    final hasText = _controller.text.trim().isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.surface, AppColors.surfaceAlt.withValues(alpha: 0.6)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.stroke),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.link_rounded, size: 19, color: AppColors.faint),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _controller,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _analyze(),
                  style: const TextStyle(fontSize: 13.5, color: AppColors.text),
                  cursorColor: AppColors.accent,
                  decoration: const InputDecoration(
                    hintText: 'Tempel tautan video YouTube di sini',
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              if (hasText)
                IconButton(
                  onPressed: _controller.clear,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  color: AppColors.faint,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Bersihkan',
                )
              else
                TextButton.icon(
                  onPressed: _paste,
                  icon: const Icon(Icons.content_paste_rounded, size: 14),
                  label: const Text('Tempel'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _analyzing ? null : _analyze,
              style: FilledButton.styleFrom(
                disabledBackgroundColor: AppColors.accent.withValues(alpha: 0.55),
                disabledForegroundColor: Colors.white,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_analyzing)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  else
                    const Icon(Icons.travel_explore_rounded, size: 19),
                  const SizedBox(width: 9),
                  Text(_analyzeLabel),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEngineBadge(BuildContext context) {
    final ready = _status?.ready ?? false;
    final color = _preparing
        ? AppColors.amber
        : ready
            ? AppColors.mint
            : AppColors.danger;
    final text = _preparing
        ? 'Menyiapkan mesin yt-dlp…'
        : ready
            ? 'Mesin siap · yt-dlp ${_status?.version ?? ''}'
            : (_engineError ?? 'Mesin belum siap');

    return InkWell(
      onTap: _preparing ? null : (ready ? _showEngineSheet : _prepareEngine),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8)],
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: AppColors.faint),
              ),
            ),
            if (_preparing)
              const SizedBox(
                width: 11,
                height: 11,
                child: CircularProgressIndicator(strokeWidth: 1.6, color: AppColors.amber),
              )
            else if (!ready)
              const Icon(Icons.refresh_rounded, size: 14, color: AppColors.danger),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyHistory(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 22),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.stroke),
            ),
            child: const Icon(Icons.download_done_rounded, size: 20, color: AppColors.faint),
          ),
          const SizedBox(height: 12),
          const Text(
            'Belum ada unduhan',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text),
          ),
          const SizedBox(height: 5),
          const Text(
            'Tempel tautan di atas lalu pilih kualitas HD, video tanpa suara, atau audio saja.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, height: 1.45, color: AppColors.faint),
          ),
        ],
      ),
    );
  }

  Future<void> _showEngineSheet() async {
    var updating = false;
    var cookiesExists = false;
    var cookiesSize = 0;
    var cookiesBusy = false;
    try {
      final status = await YtEngine.instance.cookiesStatus();
      cookiesExists = status['exists'] == true;
      cookiesSize = (status['size'] as num?)?.toInt() ?? 0;
    } catch (_) {}

    Future<void> reloadCookies(void Function(void Function()) setSheetState) async {
      try {
        final status = await YtEngine.instance.cookiesStatus();
        setSheetState(() {
          cookiesExists = status['exists'] == true;
          cookiesSize = (status['size'] as num?)?.toInt() ?? 0;
        });
      } catch (_) {}
    }

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Mesin unduhan',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'TubeGrab menjalankan yt-dlp langsung di perangkat Anda, tanpa server perantara. '
                    'Mesin diperbarui otomatis agar tetap kompatibel dengan perubahan YouTube.',
                    style: TextStyle(fontSize: 12, height: 1.5, color: AppColors.muted),
                  ),
                  const SizedBox(height: 16),
                  _sheetRow('Versi yt-dlp', _status?.version ?? '—'),
                  const SizedBox(height: 8),
                  _sheetRow('Pembaruan terakhir', _status?.update ?? '—'),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: updating
                          ? null
                          : () async {
                              setSheetState(() => updating = true);
                              try {
                                final status = await YtEngine.instance.update();
                                if (mounted) setState(() => _status = status);
                                if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                                _toast('Mesin yt-dlp diperbarui');
                              } catch (error) {
                                setSheetState(() => updating = false);
                                _toast('Gagal memperbarui: $error');
                              }
                            },
                      icon: updating
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.system_update_alt_rounded, size: 18),
                      label: Text(updating ? 'Memperbarui…' : 'Perbarui mesin sekarang'),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Divider(color: AppColors.stroke),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.cookie_outlined, size: 18, color: AppColors.muted),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Cookies YouTube (opsional)',
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: cookiesExists ? AppColors.mint.withValues(alpha: 0.12) : AppColors.surfaceAlt,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: cookiesExists ? AppColors.mint.withValues(alpha: 0.4) : AppColors.stroke,
                          ),
                        ),
                        child: Text(
                          cookiesExists ? 'Aktif · ${formatBytes(cookiesSize)}' : 'Belum diatur',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: cookiesExists ? AppColors.mint : AppColors.faint,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Gunakan bila YouTube meminta "Sign in to confirm you\'re not a bot". '
                    'Impor berkas cookies.txt (format Netscape) dari browser Anda.',
                    style: TextStyle(fontSize: 11.5, height: 1.45, color: AppColors.muted),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: cookiesBusy
                              ? null
                              : () async {
                                  setSheetState(() => cookiesBusy = true);
                                  try {
                                    final path = await YtEngine.instance.pickCookiesFile();
                                    if (path != null) {
                                      await reloadCookies(setSheetState);
                                      _toast('Cookies diimpor');
                                    }
                                  } catch (error) {
                                    _toast('Gagal mengimpor: $error');
                                  } finally {
                                    setSheetState(() => cookiesBusy = false);
                                  }
                                },
                          icon: cookiesBusy
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.file_open_rounded, size: 16),
                          label: const Text('Impor file'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: cookiesBusy
                              ? null
                              : () async {
                                  final controller = TextEditingController();
                                  final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (dialogContext) => AlertDialog(
                                      backgroundColor: AppColors.surfaceAlt,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      title: const Text(
                                        'Tempel cookies',
                                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                                      ),
                                      content: TextField(
                                        controller: controller,
                                        maxLines: 8,
                                        style: const TextStyle(fontSize: 11.5),
                                        decoration: const InputDecoration(
                                          hintText: 'Tempel isi cookies.txt (format Netscape)…',
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.of(dialogContext).pop(false),
                                          child: const Text('Batal', style: TextStyle(color: AppColors.muted)),
                                        ),
                                        TextButton(
                                          onPressed: () => Navigator.of(dialogContext).pop(true),
                                          child: const Text('Simpan'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (ok != true) return;
                                  setSheetState(() => cookiesBusy = true);
                                  try {
                                    await YtEngine.instance.saveCookies(controller.text);
                                    await reloadCookies(setSheetState);
                                    _toast('Cookies disimpan');
                                  } catch (error) {
                                    _toast('Gagal menyimpan: $error');
                                  } finally {
                                    setSheetState(() => cookiesBusy = false);
                                  }
                                },
                          icon: const Icon(Icons.content_paste_rounded, size: 16),
                          label: const Text('Tempel'),
                        ),
                      ),
                      if (cookiesExists) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: cookiesBusy
                              ? null
                              : () async {
                                  setSheetState(() => cookiesBusy = true);
                                  try {
                                    await YtEngine.instance.clearCookies();
                                    await reloadCookies(setSheetState);
                                    _toast('Cookies dihapus');
                                  } catch (error) {
                                    _toast('Gagal menghapus: $error');
                                  } finally {
                                    setSheetState(() => cookiesBusy = false);
                                  }
                                },
                          icon: const Icon(Icons.delete_outline_rounded, size: 18),
                          color: AppColors.danger,
                          tooltip: 'Hapus cookies',
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _sheetRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.faint)),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 11.5, color: AppColors.text, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Future<void> _openTask(DownloadTask task) async {
    final locator = task.locator;
    if (locator == null) return;
    try {
      await YtEngine.instance.open(locator, task.mime);
    } catch (error) {
      _toast(error.toString());
    }
  }

  Future<void> _shareTask(DownloadTask task) async {
    final locator = task.locator;
    if (locator == null) return;
    try {
      await YtEngine.instance.share(locator, task.mime);
    } catch (error) {
      _toast(error.toString());
    }
  }

  Future<void> _openItem(HistoryItem item) async {
    try {
      await _manager.openHistory(item);
    } catch (error) {
      _toast(error.toString());
    }
  }

  Future<void> _shareItem(HistoryItem item) async {
    try {
      await _manager.shareHistory(item);
    } catch (error) {
      _toast(error.toString());
    }
  }

  Future<void> _deleteItem(HistoryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surfaceAlt,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Hapus unduhan?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(
          'Berkas "${item.title}" akan dihapus dari penyimpanan.',
          style: const TextStyle(fontSize: 12.5, height: 1.5, color: AppColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal', style: TextStyle(color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Hapus', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _manager.removeHistory(item);
  }
}
