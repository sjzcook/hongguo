import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/drama.dart';
import '../../state/app_state.dart';
import '../../widgets/drama_cover.dart';
import '../player/player_page.dart';

/// 剧集详情：头图 + 简介 + 选集。
class DetailPage extends StatefulWidget {
  const DetailPage({super.key, required this.drama});

  final Drama drama;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  late Drama _drama = widget.drama;
  List<Episode> _episodes = const [];
  bool _loading = true;
  String? _error;
  bool _descExpanded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final source = context.read<AppState>().source;
    try {
      final results = await Future.wait([
        source.fetchDetail(widget.drama.id),
        source.fetchEpisodes(widget.drama.id),
      ]);
      if (!mounted) return;
      setState(() {
        _drama = results[0] as Drama;
        _episodes = results[1] as List<Episode>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _play({int index = 1, Duration position = Duration.zero}) {
    if (_episodes.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerPage(
        drama: _drama,
        episodes: _episodes,
        initialIndex: index,
        startPosition: position,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final fav = app.isFavorite(_drama.id);
    final progress = app.progressOf(_drama.id);
    final resumeIndex = progress?.episodeIndex ?? 1;
    final resumePos = Duration(milliseconds: progress?.positionMs ?? 0);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: AppColors.bg,
            leading: _CircleButton(
              icon: Icons.arrow_back_ios_new,
              onTap: () => Navigator.of(context).pop(),
            ),
            actions: [
              _CircleButton(
                icon: fav ? Icons.favorite : Icons.favorite_border,
                color: fav ? AppColors.primary : Colors.white,
                onTap: () => app.toggleFavorite(_drama.id),
              ),
              const SizedBox(width: 10),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  DramaCover(drama: _drama, radius: 0),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.0, 0.45, 1.0],
                        colors: [
                          Color(0xCC0A0A0D),
                          Color(0x330A0A0D),
                          AppColors.bg,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _drama.title,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _Pill(
                        text: _drama.isCompleted
                            ? '全 ${_drama.totalEpisodes} 集'
                            : '更新至 ${_drama.availableEpisodes} 集',
                        highlight: true,
                      ),
                      _Pill(text: _drama.category),
                      ..._drama.tags.take(3).map((t) => _Pill(text: t)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (_drama.score > 0) ...[
                        const Icon(Icons.local_fire_department,
                            size: 14, color: AppColors.gold),
                        const SizedBox(width: 3),
                        Text(
                          _drama.score.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.gold,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Text(
                        _drama.playCountText,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textTertiary,
                        ),
                      ),
                      if (_drama.actors.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _drama.actors.take(2).join(' / '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _PrimaryButton(
                          label: progress == null
                              ? '立即观看'
                              : '继续第 $resumeIndex 集',
                          icon: Icons.play_arrow_rounded,
                          onTap: () => _play(
                            index: resumeIndex,
                            position: resumePos,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _SquareButton(
                        icon: fav ? Icons.favorite : Icons.favorite_border,
                        active: fav,
                        onTap: () => app.toggleFavorite(_drama.id),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () => setState(() => _descExpanded = !_descExpanded),
                    child: Text(
                      _drama.description.isEmpty ? '暂无简介' : _drama.description,
                      maxLines: _descExpanded ? null : 3,
                      overflow: _descExpanded
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.65,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      const Text(
                        '选集',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_loading)
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        ),
                      const Spacer(),
                      if (_episodes.isNotEmpty)
                        Text(
                          '共 ${_episodes.length} 集',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textTertiary,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          if (_error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  mainAxisSpacing: 9,
                  crossAxisSpacing: 9,
                  childAspectRatio: 1.55,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final ep = _episodes[i];
                    final isCurrent = progress?.episodeIndex == ep.index;
                    return GestureDetector(
                      onTap: () => _play(index: ep.index),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? AppColors.primary.withValues(alpha: 0.16)
                              : AppColors.surfaceHigh,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isCurrent
                                ? AppColors.primary
                                : Colors.transparent,
                            width: 1,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${ep.index}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight:
                                isCurrent ? FontWeight.w700 : FontWeight.w400,
                            color: isCurrent
                                ? AppColors.primary
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                    );
                  },
                  childCount: _episodes.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, this.highlight = false});

  final String text;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: highlight
            ? AppColors.primary.withValues(alpha: 0.15)
            : AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: highlight ? FontWeight.w600 : FontWeight.w400,
          color: highlight ? AppColors.primary : AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.onTap,
    this.color = Colors.white,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 17, color: color),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.primary, AppColors.primaryDeep],
          ),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SquareButton extends StatelessWidget {
  const _SquareButton({
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Icon(
          icon,
          size: 20,
          color: active ? AppColors.primary : AppColors.textSecondary,
        ),
      ),
    );
  }
}
