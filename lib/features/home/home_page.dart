import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/drama.dart';
import '../../data/models/watch_progress.dart';
import '../../state/app_state.dart';
import '../../widgets/drama_card.dart';
import '../../widgets/drama_cover.dart';
import '../detail/detail_page.dart';
import '../search/search_page.dart';

/// 发现页：分类 + 继续观看 + 推荐流。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin {
  final _scroll = ScrollController();
  final _items = <Drama>[];

  List<String> _categories = const ['推荐'];
  String _category = '推荐';
  int _page = 0;
  bool _loading = false;
  bool _hasMore = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (!mounted) return;
    final source = context.read<AppState>().source;
    try {
      final cats = await source.categories();
      if (!mounted) return;
      setState(() => _categories = cats.isEmpty ? const ['推荐'] : cats);
    } catch (_) {
      // 分类失败不影响主流程。
    }
    await _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    if (!reset && !_hasMore) return;
    setState(() {
      _loading = true;
      if (reset) _error = null;
    });

    final source = context.read<AppState>().source;
    final nextPage = reset ? 1 : _page + 1;
    try {
      final data = await source.fetchFeed(
        page: nextPage,
        category: _category == '推荐' ? null : _category,
      );
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(data);
        _page = nextPage;
        _hasMore = data.length >= 9;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  void _onScroll() {
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) {
      _load();
    }
  }

  void _openDetail(Drama drama) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DetailPage(drama: drama)),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final appState = context.watch<AppState>();
    final history = appState.history.take(8).toList();

    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.surfaceHigh,
      onRefresh: () => _load(reset: true),
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          SliverAppBar(
            floating: true,
            backgroundColor: AppColors.bg,
            titleSpacing: 16,
            title: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.primaryDeep],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.play_arrow_rounded,
                      size: 18, color: Colors.white),
                ),
                const SizedBox(width: 8),
                const Text(
                  '红果短剧',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SearchPage()),
                ),
                icon: const Icon(Icons.search, size: 23),
              ),
              const SizedBox(width: 6),
            ],
          ),
          SliverToBoxAdapter(child: _CategoryBar(
            categories: _categories,
            selected: _category,
            onSelect: (c) {
              if (c == _category) return;
              setState(() => _category = c);
              _load(reset: true);
            },
          )),
          if (history.isNotEmpty)
            SliverToBoxAdapter(
              child: _ContinueWatching(history: history),
            ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 2),
              child: Row(
                children: [
                  Text(
                    '为你推荐',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(width: 6),
                  Icon(Icons.auto_awesome, size: 14, color: AppColors.gold),
                ],
              ),
            ),
          ),
          if (_error != null && _items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _ErrorView(message: _error!, onRetry: () => _load(reset: true)),
            )
          else if (_items.isEmpty && !_loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text('暂无内容',
                    style: TextStyle(color: AppColors.textTertiary)),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.53,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final drama = _items[i];
                    final progress = appState.progressOf(drama.id);
                    return DramaPosterCard(
                      drama: drama,
                      progress: progress?.ratio,
                      onTap: () => _openDetail(drama),
                    );
                  },
                  childCount: _items.length,
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24, top: 6),
              child: Center(
                child: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      )
                    : Text(
                        _hasMore ? '' : '— 没有更多了 —',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textTertiary,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.categories,
    required this.selected,
    required this.onSelect,
  });

  final List<String> categories;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final c = categories[i];
          final active = c == selected;
          return GestureDetector(
            onTap: () => onSelect(c),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? AppColors.primary : AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                c,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ContinueWatching extends StatelessWidget {
  const _ContinueWatching({required this.history});

  final List<WatchProgress> history;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            '继续观看',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
        SizedBox(
          height: 158,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: history.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final p = history[i];
              final fake = Drama(
                id: p.dramaId,
                title: p.dramaTitle,
                cover: p.dramaCover,
              );
              return SizedBox(
                width: 96,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: DramaCover(drama: fake, radius: 10),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                bottom: Radius.circular(10),
                              ),
                              child: LinearProgressIndicator(
                                value: p.ratio,
                                minHeight: 2.5,
                                backgroundColor: Colors.black45,
                                valueColor: const AlwaysStoppedAnimation(
                                    AppColors.primary),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 5,
                            bottom: 7,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '第${p.episodeIndex}集',
                                style: const TextStyle(
                                    fontSize: 9, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      p.dramaTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 40, color: AppColors.textTertiary),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
              ),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
