import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../data/models/drama.dart';

/// 剧集封面：网络图 + 渐变兜底，失败时永远不会出现「破图」。
class DramaCover extends StatelessWidget {
  const DramaCover({
    super.key,
    required this.drama,
    this.width,
    this.height,
    this.radius = 10,
    this.aspectRatio,
  });

  final Drama drama;
  final double? width;
  final double? height;
  final double radius;
  final double? aspectRatio;

  @override
  Widget build(BuildContext context) {
    final colors = drama.coverColors ?? AppColors.coverFor(drama.id);
    final radiusValue = BorderRadius.circular(radius);

    Widget fallback() => _GradientCover(
          colors: colors,
          title: drama.title,
          radius: radius,
        );

    Widget image = fallback();
    if (drama.cover.isNotEmpty) {
      image = CachedNetworkImage(
        imageUrl: drama.cover,
        fit: BoxFit.cover,
        fadeInDuration: const Duration(milliseconds: 220),
        placeholder: (_, _) => fallback(),
        errorWidget: (_, _, _) => fallback(),
      );
    }

    final child = ClipRRect(
      borderRadius: radiusValue,
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            image,
            // 底部压暗，保证角标文字可读。
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.center,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0x99101014)],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (aspectRatio == null) return child;
    return AspectRatio(aspectRatio: aspectRatio!, child: child);
  }
}

class _GradientCover extends StatelessWidget {
  const _GradientCover({
    required this.colors,
    required this.title,
    required this.radius,
  });

  final List<Color> colors;
  final String title;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final initial = title.isEmpty ? '剧' : title.substring(0, 1);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w900,
            color: Colors.white.withValues(alpha: 0.22),
          ),
        ),
      ),
    );
  }
}
