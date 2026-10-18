import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/drama.dart';
import '../../data/models/user_profile.dart';
import '../../data/models/watch_progress.dart';
import '../../state/app_state.dart';
import '../../widgets/drama_card.dart';
import '../detail/detail_page.dart';
import '../login/login_page.dart';
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

  Future<void> _login(BuildContext context) async {
    final ok = await LoginPage.show(context, reason: '登录后解锁全部剧集');
    if (!ok || !context.mounted) return;
    final name = context.read<AppState>().profile?.nickname ?? '果友';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('欢迎回来，$name')));
  }

  Future<void> _logout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceHigh,
        title: const Text('退出登录', style: TextStyle(fontSize: 16)),
        content: const Text(
          '退出后付费剧集需要重新登录才能观看。\n本机的收藏与观看历史会保留。',
          style: TextStyle(
            fontSize: 13,
            height: 1.6,
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出',
                style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
    if (ok == true) await app.logout();
  }

  @override
  Widget build(BuildContext context) {
    final profile = app.profile;

    return GestureDetector(
      onTap: profile == null ? () => _login(context) : null,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.primary.withValues(alpha: profile == null ? 0.22 : 0.30),
              AppColors.surfaceHigh,
            ],
          ),
          border: Border.all(
            color: profile == null
                ? Colors.transparent
                : AppColors.primary.withValues(alpha: 0.25),
            width: 0.8,
          ),
        ),
        child: Row(
          children: [
            _Avatar(profile: profile),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          profile?.nickname ?? '未登录',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (profile != null && profile.isVip) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: AppColors.gold.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'VIP',
                            style: TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.gold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    profile == null
                        ? '登录后可解锁全部剧集，收藏与进度云端同步'
                        : '${profile.modeLabel} · ${profile.maskedPhone}'
                            ' · 收藏 ${app.favorites.length} · 观看 ${app.history.length}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (profile == null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryDeep],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  '登录',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              )
            else
              GestureDetector(
                onTap: () => _logout(context),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    '退出',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.profile});

  final UserProfile? profile;

  @override
  Widget build(BuildContext context) {
    final url = profile?.avatar ?? '';
    final fallback = Container(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [AppColors.primary, AppColors.gold]),
      ),
      alignment: Alignment.center,
      child: profile == null
          ? const Icon(Icons.person, color: Colors.white, size: 26)
          : Text(
              profile!.initial,
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
    );

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 1.4,
        ),
      ),
      child: ClipOval(
        child: url.isEmpty
            ? fallback
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
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
