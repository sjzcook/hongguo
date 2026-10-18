import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/drama.dart';
import '../../data/models/watch_progress.dart';
import '../../state/app_state.dart';
import '../../widgets/drama_card.dart';
import '../detail/detail_page.dart';
import '../settings/settings_page.dart';

/// 我的：收藏与观看历史（全部存本机）。
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final app = context.watch<AppState>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.bg,
            title: const Text('我的',
                style: TextStyle(fontWeight: FontWeight.w700)),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings_outlined, size: 21),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                ),
              ),
            ],
          ),
          SliverToBoxAdapter(child: _ProfileCard(app: app)),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabHeader(
              TabBar(
                controller: _tab,
                labelColor: AppColors.textPrimary,
                unselectedLabelColor: AppColors.textTertiary,
                labelStyle: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700),
                indicatorColor: AppColors.primary,
                indicatorSize: TabBarIndicatorSize.label,
                dividerColor: Colors.transparent,
                tabs: [
                  Tab(text: '收藏 ${app.favorites.length}'),
                  Tab(text: '历史 ${app.history.length}'),
                ],
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tab,
          children: [
            _FavoritesGrid(app: app),
            _HistoryList(app: app),
          ],
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.22),
            AppColors.surfaceHigh,
          ],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.gold],
              ),
            ),
            child: const Icon(Icons.person, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '本地用户',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '收藏 ${app.favorites.length} · 观看 ${app.history.length} · 数据仅存本机',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              '免登录',
              style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _FavoritesGrid extends StatelessWidget {
  const _FavoritesGrid({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final ids = app.favorites.toList();
    if (ids.isEmpty) {
      return const _Empty(
        icon: Icons.favorite_border,
        text: '还没有收藏的短剧',
        hint: '在详情页点♡即可收藏',
      );
    }
    return FutureBuilder<List<Drama>>(
      future: _resolve(app, ids),
      builder: (context, snapshot) {
        final list = snapshot.data ?? const <Drama>[];
        if (snapshot.connectionState == ConnectionState.waiting && list.isEmpty) {
          return const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary,
              ),
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 14,
            crossAxisSpacing: 10,
            childAspectRatio: 0.53,
          ),
          itemCount: list.length,
          itemBuilder: (context, i) {
            final drama = list[i];
            return DramaPosterCard(
              drama: drama,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => DetailPage(drama: drama)),
              ),
            );
          },
        );
      },
    );
  }

  Future<List<Drama>> _resolve(AppState app, List<String> ids) async {
    final result = <Drama>[];
    for (final id in ids) {
      try {
        result.add(await app.source.fetchDetail(id));
      } catch (_) {
        // 站源里已下架的剧直接跳过。
      }
    }
    return result;
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final history = app.history;
    if (history.isEmpty) {
      return const _Empty(
        icon: Icons.history,
        text: '还没有观看记录',
        hint: '看过的剧会出现在这里，支持断点续播',
      );
    }
    final fmt = DateFormat('MM-dd HH:mm');
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      itemCount: history.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (context, i) {
        final p = history[i];
        return DramaWideCard(
          drama: Drama(
            id: p.dramaId,
            title: p.dramaTitle,
            cover: p.dramaCover,
          ),
          progress: p.ratio,
          subtitle:
              '看到第 ${p.episodeIndex} 集 · ${_stage(p)} · ${fmt.format(p.updatedAt)}',
          onTap: () => _open(context, p),
          trailing: IconButton(
            icon: const Icon(Icons.close, size: 17, color: AppColors.textTertiary),
            onPressed: () => app.removeHistory(p.dramaId),
          ),
        );
      },
    );
  }

  String _stage(WatchProgress p) {
    if (p.finished) return '已看完';
    final percent = (p.ratio * 100).round();
    return '看了 $percent%';
  }

  Future<void> _open(BuildContext context, WatchProgress p) async {
    try {
      final drama = await app.source.fetchDetail(p.dramaId);
      if (!context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DetailPage(drama: drama)),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('该剧在当前站源已不可用')));
    }
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text, required this.hint});

  final IconData icon;
  final String text;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: AppColors.textTertiary),
          const SizedBox(height: 12),
          Text(text,
              style: const TextStyle(
                  fontSize: 13.5, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          Text(hint,
              style: const TextStyle(
                  fontSize: 11.5, color: AppColors.textTertiary)),
        ],
      ),
    );
  }
}

class _TabHeader extends SliverPersistentHeaderDelegate {
  _TabHeader(this.tabBar);

  final TabBar tabBar;

  @override
  double get minExtent => 46;

  @override
  double get maxExtent => 46;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(color: AppColors.bg, child: tabBar);
  }

  @override
  bool shouldRebuild(covariant _TabHeader oldDelegate) => false;
}
