import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/download_options.dart';
import '../models/video_info.dart';
import '../services/download_manager.dart';

class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, required this.info});

  final VideoInfo info;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  late final Map<DownloadKind, List<DownloadOption>> _options;

  DownloadKind _kind = DownloadKind.videoAudio;
  DownloadOption? _selected;

  @override
  void initState() {
    super.initState();
    _options = {
      for (final kind in DownloadKind.values) kind: buildDownloadOptions(widget.info, kind),
    };
    _selected = defaultOption(_options[_kind]!, _kind);
    if (_selected == null) {
      for (final kind in DownloadKind.values) {
        if (_options[kind]!.isNotEmpty) {
          _kind = kind;
          _selected = defaultOption(_options[kind]!, kind);
          break;
        }
      }
    }
  }

  void _selectKind(DownloadKind kind) {
    if (_options[kind]!.isEmpty) return;
    setState(() {
      _kind = kind;
      _selected = defaultOption(_options[kind]!, kind);
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _startDownload() {
    final option = _selected;
    if (option == null) return;
    final manager = DownloadManager.instance;
    if (manager.isBusy) {
      _toast('Masih ada unduhan yang berjalan');
      return;
    }
    unawaited(manager.start(info: widget.info, option: option));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final options = _options[_kind]!;
    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: _buildBottomBar(),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 216,
            backgroundColor: AppColors.background,
            surfaceTintColor: Colors.transparent,
            systemOverlayStyle: SystemUiOverlayStyle.light,
            leadingWidth: 64,
            leading: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Center(
                child: _RoundIconButton(
                  icon: Icons.arrow_back_rounded,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.parallax,
              background: _buildHero(),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            sliver: SliverList.list(
              children: [
                Text(
                  widget.info.title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.32, letterSpacing: -0.3),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _MetaPill(icon: Icons.person_outline_rounded, label: widget.info.uploader),
                    if (widget.info.duration != null)
                      _MetaPill(icon: Icons.schedule_rounded, label: formatDuration(widget.info.duration)),
                    if ((widget.info.viewCount ?? 0) > 0)
                      _MetaPill(icon: Icons.visibility_outlined, label: formatCompactCount(widget.info.viewCount)),
                    if (widget.info.uploadedAt != null)
                      _MetaPill(icon: Icons.calendar_today_rounded, label: formatUploadDate(widget.info.uploadedAt)),
                  ],
                ),
                const SizedBox(height: 22),
                _buildModeSelector(),
                const SizedBox(height: 8),
                Text(
                  _kindHint(),
                  style: const TextStyle(fontSize: 11, color: AppColors.faint, height: 1.4),
                ),
                const SizedBox(height: 18),
                if (options.isEmpty)
                  _buildNoFormats()
                else
                  for (final option in options)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _QualityTile(
                        option: option,
                        selected: _selected == option,
                        onTap: () => setState(() => _selected = option),
                      ),
                    ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 13, color: AppColors.faint),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        _kind == DownloadKind.videoAudio
                            ? 'Video dan audio diunduh terpisah lalu digabung otomatis menjadi satu berkas.'
                            : _kind == DownloadKind.videoOnly
                                ? 'Berkas berisi gambar saja; tidak ada suara di dalamnya.'
                                : 'Audio diekstrak dengan FFmpeg sesuai format yang dipilih.',
                        style: const TextStyle(fontSize: 10.5, color: AppColors.faint, height: 1.45),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: MediaQuery.paddingOf(context).bottom + 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHero() {
    final info = widget.info;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (info.thumbnail.isEmpty)
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [AppColors.surfaceAlt, AppColors.surface]),
            ),
          )
        else
          Image.network(
            info.thumbnail,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [AppColors.surfaceAlt, AppColors.surface]),
              ),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.background.withValues(alpha: 0.45),
                AppColors.background.withValues(alpha: 0.2),
                AppColors.background,
              ],
              stops: const [0, 0.55, 1],
            ),
          ),
        ),
        if (info.duration != null)
          Positioned(
            right: 20,
            bottom: 18,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              ),
              child: Text(
                formatDuration(info.duration),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildModeSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Row(
        children: [
          for (final kind in DownloadKind.values)
            Expanded(
              child: _ModeTab(
                kind: kind,
                selected: _kind == kind,
                enabled: _options[kind]!.isNotEmpty,
                onTap: () => _selectKind(kind),
              ),
            ),
        ],
      ),
    );
  }

  String _kindHint() {
    switch (_kind) {
      case DownloadKind.videoAudio:
        return 'Kualitas HD hingga 4K. Audio otomatis disertakan.';
      case DownloadKind.videoOnly:
        return 'Untuk diedit ulang atau dikompres sendiri.';
      case DownloadKind.audioOnly:
        return 'M4A kualitas asli atau MP3 dengan bitrate pilihan.';
    }
  }

  Widget _buildNoFormats() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.stroke),
      ),
      child: const Text(
        'Format ini tidak tersedia untuk video tersebut. Coba pilihan lain.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.5),
      ),
    );
  }

  Widget _buildBottomBar() {
    final option = _selected;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.stroke)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    option?.container ?? 'PILIH FORMAT',
                    style: const TextStyle(
                      fontSize: 9.5,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w600,
                      color: AppColors.faint,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    option?.sizeLabel ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.muted),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: option == null ? null : _startDownload,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.download_rounded, size: 19),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Unduh ${option?.title ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.kind,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final DownloadKind kind;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  IconData get _icon => switch (kind) {
        DownloadKind.videoAudio => Icons.movie_rounded,
        DownloadKind.videoOnly => Icons.videocam_rounded,
        DownloadKind.audioOnly => Icons.music_note_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          height: 46,
          decoration: BoxDecoration(
            color: selected ? AppColors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_icon, size: 14, color: selected ? Colors.white : AppColors.muted),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      kind.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : AppColors.muted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 1),
              Text(
                kind.hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 8.5,
                  letterSpacing: 0.2,
                  color: selected ? Colors.white.withValues(alpha: 0.72) : AppColors.faint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QualityTile extends StatelessWidget {
  const _QualityTile({required this.option, required this.selected, required this.onTap});

  final DownloadOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accent.withValues(alpha: 0.08) : AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppColors.accent.withValues(alpha: 0.75) : AppColors.stroke,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          option.title,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: selected ? AppColors.text : AppColors.text.withValues(alpha: 0.9),
                          ),
                        ),
                        if (option.badge.isNotEmpty) _MiniChip(option.badge, highlighted: selected),
                        _MiniChip(option.container),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      option.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatBytes(option.bytes),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.muted),
                  ),
                  const SizedBox(height: 7),
                  _RadioDot(selected: selected),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadioDot extends StatelessWidget {
  const _RadioDot({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? AppColors.accent : AppColors.stroke,
          width: selected ? 1.6 : 1.2,
        ),
        color: selected ? AppColors.accent : Colors.transparent,
      ),
      child: selected ? const Icon(Icons.check_rounded, size: 12, color: Colors.white) : null,
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip(this.label, {this.highlighted = false});

  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: highlighted ? AppColors.accent.withValues(alpha: 0.18) : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: highlighted ? AppColors.accent.withValues(alpha: 0.4) : AppColors.stroke,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: highlighted ? AppColors.accent : AppColors.muted,
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: AppColors.faint),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10.5, color: AppColors.muted, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(side: BorderSide(color: Colors.white24)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, size: 19, color: Colors.white),
        ),
      ),
    );
  }
}
