import 'dart:ui' show Color;

/// 剧集连载状态。
enum DramaStatus {
  ongoing('连载中'),
  completed('已完结');

  const DramaStatus(this.label);
  final String label;
}

/// 榜单类型。[slug] 用于站源请求，[label] 用于展示。
enum RankingType {
  hot('hot', '热播榜', '本周热度最高'),
  newest('new', '新剧榜', '最新上线'),
  finished('finished', '完结榜', '一次看到爽'),
  ai('ai', '漫剧榜', 'AI 与漫剧专场');

  const RankingType(this.slug, this.label, this.subtitle);
  final String slug;
  final String label;
  final String subtitle;
}

/// 一部短剧。
class Drama {
  const Drama({
    required this.id,
    required this.title,
    this.cover = '',
    this.description = '',
    this.category = '都市',
    this.tags = const [],
    this.actors = const [],
    this.totalEpisodes = 0,
    this.updatedEpisodes = 0,
    this.status = DramaStatus.ongoing,
    this.playCount = 0,
    this.score = 0,
    this.source = 'demo',
    this.coverColors,
  });

  final String id;
  final String title;
  final String cover;
  final String description;
  final String category;
  final List<String> tags;
  final List<String> actors;
  final int totalEpisodes;
  final int updatedEpisodes;
  final DramaStatus status;
  final int playCount;
  final double score;
  final String source;
  final List<Color>? coverColors;

  bool get isCompleted => status == DramaStatus.completed;

  int get availableEpisodes =>
      updatedEpisodes > 0 ? updatedEpisodes : totalEpisodes;

  String get playCountText {
    if (playCount >= 100000000) {
      return '${(playCount / 100000000).toStringAsFixed(1)}亿播放';
    }
    if (playCount >= 10000) {
      return '${(playCount / 10000).toStringAsFixed(1)}万播放';
    }
    return '$playCount 播放';
  }

  Drama copyWith({int? updatedEpisodes, int? totalEpisodes}) => Drama(
        id: id,
        title: title,
        cover: cover,
        description: description,
        category: category,
        tags: tags,
        actors: actors,
        totalEpisodes: totalEpisodes ?? this.totalEpisodes,
        updatedEpisodes: updatedEpisodes ?? this.updatedEpisodes,
        status: status,
        playCount: playCount,
        score: score,
        source: source,
        coverColors: coverColors,
      );

  factory Drama.fromJson(Map<String, dynamic> json, {String source = 'hongguo'}) {
    final episodes = json['episode_count'] ??
        json['totalEpisodes'] ??
        json['total_episodes'] ??
        json['total'] ??
        0;
    final tags = json['tags'] ?? json['labels'];
    final actors = json['actors'] ?? json['cast'];
    return Drama(
      id: '${json['id'] ?? json['drama_id'] ?? json['series_id'] ?? json['book_id'] ?? ''}',
      title: '${json['title'] ?? json['name'] ?? json['series_title'] ?? json['series_name'] ?? '未命名'}',
      cover: '${json['cover'] ?? json['thumb_url'] ?? json['cover_url'] ?? json['poster'] ?? ''}',
      description: '${json['description'] ?? json['abstract'] ?? json['desc'] ?? ''}',
      category: '${json['category'] ?? json['category_name'] ?? json['genre'] ?? '都市'}',
      tags: tags is List ? tags.map((e) => '$e').toList() : const [],
      actors: actors is List ? actors.map((e) => '$e').toList() : const [],
      totalEpisodes: int.tryParse('$episodes') ?? 0,
      updatedEpisodes: int.tryParse('${json['updated_episodes'] ?? json['latest_episode'] ?? 0}') ?? 0,
      status: '${json['status'] ?? ''}'.contains('完结') ||
              json['is_completed'] == true
          ? DramaStatus.completed
          : DramaStatus.ongoing,
      playCount: int.tryParse('${json['play_count'] ?? json['playCount'] ?? 0}') ?? 0,
      score: double.tryParse('${json['score'] ?? json['rating'] ?? 0}') ?? 0,
      source: source,
    );
  }
}

/// 一集。
class Episode {
  const Episode({
    required this.index,
    required this.title,
    this.videoUrl = '',
    this.duration = Duration.zero,
    this.locked = false,
  });

  final int index;
  final String title;
  final String videoUrl;
  final Duration duration;
  final bool locked;

  String get label => '第 $index 集';

  factory Episode.fromJson(Map<String, dynamic> json) {
    final rawDuration = json['duration'] ?? json['duration_seconds'] ?? 0;
    final durationValue = double.tryParse('$rawDuration') ?? 0;
    final duration = rawDuration is num && rawDuration > 1000
        ? Duration(milliseconds: durationValue.round())
        : Duration(seconds: durationValue.round());
    return Episode(
      index: int.tryParse('${json['index'] ?? json['episode'] ?? json['vid_index'] ?? json['episode_index'] ?? 1}') ?? 1,
      title: '${json['title'] ?? json['name'] ?? json['episode_title'] ?? ''}',
      // 只接收可由标准播放器直接播放的 URL。加密参数/密钥字段不在客户端解密。
      videoUrl: '${json['video_url'] ?? json['url'] ?? json['play_url'] ?? json['playUrl'] ?? json['main_url'] ?? ''}',
      duration: duration,
      locked: json['locked'] == true ||
          json['is_vip'] == true ||
          json['is_locked'] == true,
    );
  }
}
