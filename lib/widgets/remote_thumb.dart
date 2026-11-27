import 'package:flutter/material.dart';

import '../core/theme.dart';

class RemoteThumb extends StatelessWidget {
  const RemoteThumb({
    super.key,
    required this.url,
    this.width = 64,
    this.height = 48,
    this.radius = 10,
  });

  final String url;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: url.isEmpty
            ? _placeholder()
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _placeholder(),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return _placeholder(showSpinner: true);
                },
              ),
      ),
    );
  }

  Widget _placeholder({bool showSpinner = false}) {
    return Container(
      color: AppColors.surfaceAlt,
      alignment: Alignment.center,
      child: showSpinner
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 1.6, color: AppColors.faint),
            )
          : const Icon(Icons.movie_outlined, size: 18, color: AppColors.faint),
    );
  }
}
