import 'dart:async';

import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/download_item.dart';
import 'remote_thumb.dart';

class ActiveDownloadCard extends StatelessWidget {
  const ActiveDownloadCard({
    super.key,
    required this.task,
    required this.onCancel,
    required this.onDismiss,
    required this.onOpen,
    required this.onShare,
  });

  final DownloadTask task;
  final VoidCallback onCancel;
  final VoidCallback onDismiss;
  final VoidCallback onOpen;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final running = !task.isFinished;
    final preparing = task.status == TaskStatus.preparing;
    final activity = task.activity;
    final done = task.status == TaskStatus.done;
    final failed = task.status == TaskStatus.failed || task.status == TaskStatus.canceled;
    final accent = done
        ? AppColors.mint
        : failed
            ? AppColors.danger
            : AppColors.accent;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
        boxShadow: running
            ? [
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.10),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RemoteThumb(url: task.thumbnail, width: 62, height: 46, radius: 10),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.3),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceAlt,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.stroke),
                          ),
                          child: Text(
                            task.label,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.muted,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            task.statusLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11.5, color: accent, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (running)
                IconButton(
                  onPressed: onCancel,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: AppColors.muted,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Batalkan',
                ),
            ],
          ),
          if (running) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              // Before the first byte arrives there is nothing to measure, so the
              // bar sweeps to show the engine is working instead of sitting at 0%.
              child: preparing
                  ? const LinearProgressIndicator(
                      minHeight: 6,
                      color: AppColors.accent,
                      backgroundColor: AppColors.stroke,
                    )
                  : SizedBox(
                      height: 6,
                      child: Stack(
                        children: [
                          Container(color: AppColors.stroke),
                          FractionallySizedBox(
                            widthFactor: task.overallProgress.clamp(0.02, 1),
                            child: Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [AppColors.accent, AppColors.accentWarm],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            if (activity != null) ...[
              Row(
                children: [
                  const Icon(Icons.bolt_rounded, size: 12, color: AppColors.faint),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      activity,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10.5, color: AppColors.faint, height: 1.3),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
            ],
            Row(
              children: [
                Text(
                  '${(task.overallProgress * 100).round()}%',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.text),
                ),
                const Spacer(),
                if (task.status == TaskStatus.processing)
                  const Text(
                    'Memproses…',
                    style: TextStyle(fontSize: 11.5, color: AppColors.muted),
                  )
                else if (task.status == TaskStatus.downloading && task.etaSeconds > 0)
                  Text(
                    'Sisa ${formatEta(task.etaSeconds)}',
                    style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                  )
                else
                  _ElapsedText(startedAt: task.startedAt),
              ],
            ),
            if (task.status == TaskStatus.downloading &&
                (task.speedBytesPerSecond != null || task.totalBytes != null)) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.speed_rounded, size: 12, color: AppColors.faint),
                  const SizedBox(width: 5),
                  if (task.speedBytesPerSecond != null)
                    Text(
                      formatSpeed(task.speedBytesPerSecond),
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                  if (task.speedBytesPerSecond != null && task.totalBytes != null)
                    const Text(
                      '  ·  ',
                      style: TextStyle(fontSize: 11.5, color: AppColors.faint),
                    ),
                  if (task.totalBytes != null)
                    Flexible(
                      child: Text(
                        task.downloadedBytes != null
                            ? '${formatBytes(task.downloadedBytes)} / ${formatBytes(task.totalBytes)}'
                            : formatBytes(task.totalBytes),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                      ),
                    ),
                ],
              ),
            ],
          ],
          if (done) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.check_circle_rounded, size: 15, color: AppColors.mint),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    formatBytes(task.bytes),
                    style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                  ),
                ),
                _ActionButton(label: 'Buka', onTap: onOpen),
                const SizedBox(width: 6),
                _ActionButton(label: 'Bagikan', onTap: onShare),
                const SizedBox(width: 6),
                _ActionButton(label: 'Tutup', onTap: onDismiss, subtle: true),
              ],
            ),
          ],
          if (failed) ...[
            if (task.error != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  task.error!,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: AppColors.danger, height: 1.35),
                ),
              ),
            ],
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: _ActionButton(label: 'Tutup', onTap: onDismiss, subtle: true),
            ),
          ],
        ],
      ),
    );
  }
}

/// Ticking counter so a slow step (resolving formats, waiting on YouTube) still
/// looks alive instead of frozen at 0%.
class _ElapsedText extends StatefulWidget {
  const _ElapsedText({required this.startedAt});

  final DateTime startedAt;

  @override
  State<_ElapsedText> createState() => _ElapsedTextState();
}

class _ElapsedTextState extends State<_ElapsedText> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = DateTime.now().difference(widget.startedAt).inSeconds;
    return Text(
      seconds < 1 ? 'Menghubungi YouTube…' : '${formatEta(seconds)} berjalan',
      style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.onTap, this.subtle = false});

  final String label;
  final VoidCallback onTap;
  final bool subtle;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        foregroundColor: subtle ? AppColors.muted : AppColors.text,
        backgroundColor: AppColors.surfaceAlt,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColors.stroke),
        ),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
    );
  }
}
