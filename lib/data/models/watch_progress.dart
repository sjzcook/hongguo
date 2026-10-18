import 'dart:convert';

/// 单部剧的观看进度，用于断点续播。
class WatchProgress {
  const WatchProgress({
    required this.dramaId,
    required this.episodeIndex,
    required this.positionMs,
    required this.durationMs,
    required this.updatedAt,
    this.dramaTitle = '',
    this.dramaCover = '',
  });

  final String dramaId;
  final String dramaTitle;
  final String dramaCover;
  final int episodeIndex;
  final int positionMs;
  final int durationMs;
  final DateTime updatedAt;

  double get ratio =>
      durationMs <= 0 ? 0 : (positionMs / durationMs).clamp(0.0, 1.0);

  bool get finished => durationMs > 0 && positionMs / durationMs > 0.95;

  WatchProgress copyWith({
    int? episodeIndex,
    int? positionMs,
    int? durationMs,
    String? dramaTitle,
    String? dramaCover,
    DateTime? updatedAt,
  }) =>
      WatchProgress(
        dramaId: dramaId,
        dramaTitle: dramaTitle ?? this.dramaTitle,
        dramaCover: dramaCover ?? this.dramaCover,
        episodeIndex: episodeIndex ?? this.episodeIndex,
        positionMs: positionMs ?? this.positionMs,
        durationMs: durationMs ?? this.durationMs,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'dramaId': dramaId,
        'dramaTitle': dramaTitle,
        'dramaCover': dramaCover,
        'episodeIndex': episodeIndex,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory WatchProgress.fromJson(Map<String, dynamic> json) => WatchProgress(
        dramaId: '${json['dramaId'] ?? ''}',
        dramaTitle: '${json['dramaTitle'] ?? ''}',
        dramaCover: '${json['dramaCover'] ?? ''}',
        episodeIndex: (json['episodeIndex'] as num?)?.toInt() ?? 1,
        positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
        updatedAt:
            DateTime.tryParse('${json['updatedAt']}') ?? DateTime.now(),
      );

  static List<WatchProgress> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final data = jsonDecode(raw);
      if (data is! List) return const [];
      return data
          .whereType<Map<String, dynamic>>()
          .map(WatchProgress.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
