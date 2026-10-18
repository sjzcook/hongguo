import 'package:flutter/foundation.dart';

import '../data/local/local_store.dart';
import '../data/models/drama.dart';
import '../data/models/watch_progress.dart';
import '../data/source/demo_source.dart';
import '../data/source/drama_source.dart';
import '../data/source/hongguo_source.dart';

/// 全局状态：站源、收藏、观看历史、播放偏好。
///
/// 用最朴素的 [ChangeNotifier]，避免为一个客户端引入过重的状态框架。
class AppState extends ChangeNotifier {
  AppState(this._store)
      : _favorites = _store.favorites,
        _history = _store.history {
    _source = _buildSource(_store.sourceId);
  }

  final LocalStore _store;

  late DramaSource _source;
  Set<String> _favorites;
  List<WatchProgress> _history;
  bool _historyDirty = false;

  DramaSource get source => _source;
  Set<String> get favorites => _favorites;
  List<WatchProgress> get history {
    if (_historyDirty) {
      _history = _store.history;
      _historyDirty = false;
    }
    return _history;
  }

  /// 可切换的站源描述。接入真实站源时在这里注册。
  List<SourceOption> get sourceOptions => [
        const SourceOption(
          id: 'demo',
          name: '演示站源',
          description: '内置离线剧库，开箱即用',
          ready: true,
        ),
        SourceOption(
          id: 'hongguo',
          name: '红果',
          description: hongguoGateway.isEmpty
              ? '需配置网关地址（见 README）'
              : '官方通道已配置',
          ready: hongguoGateway.isNotEmpty,
        ),
      ];

  /// 红果网关地址，接入自建解析服务后填入即可（见 README）。
  static const hongguoGateway = String.fromEnvironment(
    'HONGGUO_GATEWAY',
    defaultValue: '',
  );

  DramaSource _buildSource(String id) {
    if (id == 'hongguo' && hongguoGateway.isNotEmpty) {
      return HongguoDramaSource(baseUrl: hongguoGateway);
    }
    return DemoDramaSource();
  }

  Future<void> switchSource(String id) async {
    if (_source.id == id) return;
    await _source.dispose();
    _source = _buildSource(id);
    await _store.setSourceId(id);
    notifyListeners();
  }

  bool isFavorite(String dramaId) => _favorites.contains(dramaId);

  Future<void> toggleFavorite(String dramaId) async {
    _favorites = await _store.toggleFavorite(dramaId);
    notifyListeners();
  }

  WatchProgress? progressOf(String dramaId) => _store.progressOf(dramaId);

  Future<void> saveProgress({
    required Drama drama,
    required int episodeIndex,
    required Duration position,
    required Duration duration,
  }) async {
    await _store.saveProgress(
      WatchProgress(
        dramaId: drama.id,
        dramaTitle: drama.title,
        dramaCover: drama.cover,
        episodeIndex: episodeIndex,
        positionMs: position.inMilliseconds,
        durationMs: duration.inMilliseconds,
        updatedAt: DateTime.now(),
      ),
    );
    _historyDirty = true;
    notifyListeners();
  }

  Future<void> removeHistory(String dramaId) async {
    await _store.removeProgress(dramaId);
    _historyDirty = true;
    notifyListeners();
  }

  Future<void> clearHistory() async {
    await _store.clearHistory();
    _historyDirty = true;
    notifyListeners();
  }

  bool get autoPlay => _store.autoPlay;
  Future<void> setAutoPlay(bool value) async {
    await _store.setAutoPlay(value);
    notifyListeners();
  }

  double get speed => _store.speed;
  Future<void> setSpeed(double value) async {
    await _store.setSpeed(value);
    notifyListeners();
  }

  String get quality => _store.quality;
  Future<void> setQuality(String value) async {
    await _store.setQuality(value);
    notifyListeners();
  }

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }
}

/// 站源选项，供设置页展示。
class SourceOption {
  const SourceOption({
    required this.id,
    required this.name,
    required this.description,
    required this.ready,
  });

  final String id;
  final String name;
  final String description;
  final bool ready;
}
