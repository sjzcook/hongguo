import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../data/models/drama.dart';
import 'drama_cover.dart';

/// 竖版剧卡，用于网格流。
class DramaPosterCard extends StatelessWidget {
  const DramaPosterCard({
    super.key,
    required this.drama,
    this.onTap,
    this.progress,
  });

  final Drama drama;
  final VoidCallback? onTap;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: DramaCover(drama: drama, radius: 12),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(12),
                    ),
                    child: _FooterChip(drama: drama),
                  ),
                ),
                if (progress != null && progress! > 0)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LinearProgressIndicator(
                      value: progress!.clamp(0.0, 1.0),
                      minHeight: 2.5,
                      backgroundColor: Colors.black38,
                      valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 7),
          Text(
            drama.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              height: 1.3,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            drama.isCompleted
                ? '全 ${drama.totalEpisodes} 集'
                : '更新至 ${drama.availableEpisodes} 集',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _FooterChip extends StatelessWidget {
  const _FooterChip({required this.drama});

  final Drama drama;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 14, 6, 5),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Color(0xCC000000)],
        ),
      ),
      child: Row(
        children: [
          if (drama.score > 0) ...[
            const Icon(Icons.local_fire_department,
                size: 11, color: AppColors.gold),
            const SizedBox(width: 2),
            Text(
              drama.score.toStringAsFixed(1),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.gold,
              ),
            ),
          ] else
            Text(
              drama.category,
              style: const TextStyle(fontSize: 10, color: Colors.white70),
            ),
        ],
      ),
    );
  }
}

/// 横向卡片，用于「继续观看」和搜索结果。
class DramaWideCard extends StatelessWidget {
  const DramaWideCard({
    super.key,
    required this.drama,
    this.onTap,
    this.subtitle,
    this.trailing,
    this.progress,
  });

  final Drama drama;
  final VoidCallback? onTap;
  final String? subtitle;
  final Widget? trailing;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 74,
              height: 99,
              child: Stack(
                children: [
                  Positioned.fill(child: DramaCover(drama: drama, radius: 8)),
                  if (progress != null && progress! > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(8),
                        ),
                        child: LinearProgressIndicator(
                          value: progress!.clamp(0.0, 1.0),
                          minHeight: 2.5,
                          backgroundColor: Colors.black45,
                          valueColor:
                              const AlwaysStoppedAnimation(AppColors.primary),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    drama.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle ??
                        (drama.isCompleted
                            ? '全 ${drama.totalEpisodes} 集 · ${drama.category}'
                            : '更新至 ${drama.availableEpisodes} 集 · ${drama.category}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    drama.description.isEmpty ? drama.playCountText : drama.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.45,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
  }
}

/// 榜单行：大号名次 + 海报 + 标题。
class RankRow extends StatelessWidget {
  const RankRow({
    super.key,
    required this.rank,
    required this.drama,
    this.onTap,
  });

  final int rank;
  final Drama drama;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isTop = rank <= 3;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              child: Text(
                '$rank',
                style: TextStyle(
                  fontSize: isTop ? 20 : 16,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w800,
                  color: isTop ? AppColors.primary : AppColors.textTertiary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 56,
              height: 75,
              child: DramaCover(drama: drama, radius: 7),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    drama.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${drama.category} · ${drama.playCountText}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              drama.isCompleted ? Icons.check_circle_outline : Icons.play_circle_outline,
              size: 19,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
