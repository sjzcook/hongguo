import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/watch_progress.dart';

/// 本地持久化：收藏、观看历史、偏好设置。
///
/// 与真果鉴一致——账号体系不接通，所有数据只存在本机。
class LocalStore {
  LocalStore._(this._prefs);

  final SharedPreferences _prefs;

  static const _kFavorites = 'hg.favorites';
  static const _kHistory = 'hg.history';
  static const _kSource = 'hg.source';
  static const _kAutoPlay = 'hg.autoPlay';
  static const _kQuality = 'hg.quality';
  static const _kSpeed = 'hg.speed';

  static Future<LocalStore> open() async {
    final prefs = await SharedPreferences.getInstance();
    return LocalStore._(prefs);
  }

  // ---- 收藏 ----

  Set<String> get favorites {
    final raw = _prefs.getStringList(_kFavorites) ?? const [];
    return raw.toSet();
  }

  bool isFavorite(String dramaId) => favorites.contains(dramaId);

  Future<Set<String>> toggleFavorite(String dramaId) async {
    final current = favorites;
    if (!current.remove(dramaId)) current.add(dramaId);
    await _prefs.setStringList(_kFavorites, current.toList());
    return current;
  }

  // ---- 观看历史 ----

  List<WatchProgress> get history {
    final list = WatchProgress.decodeList(_prefs.getString(_kHistory));
    final copy = [...list]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return copy;
  }

  WatchProgress? progressOf(String dramaId) {
    for (final p in history) {
      if (p.dramaId == dramaId) return p;
    }
    return null;
  }

  Future<void> saveProgress(WatchProgress progress) async {
    final list = history.where((p) => p.dramaId != progress.dramaId).toList();
    list.insert(0, progress);
    // 最多保留 200 条，避免无限增长。
    final trimmed = list.take(200).toList();
    await _prefs.setString(
      _kHistory,
      jsonEncode(trimmed.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> removeProgress(String dramaId) async {
    final list = history.where((p) => p.dramaId != dramaId).toList();
    await _prefs.setString(
      _kHistory,
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> clearHistory() async => _prefs.remove(_kHistory);

  // ---- 偏好 ----

  String get sourceId => _prefs.getString(_kSource) ?? 'demo';
  Future<void> setSourceId(String id) async => _prefs.setString(_kSource, id);

  bool get autoPlay => _prefs.getBool(_kAutoPlay) ?? true;
  Future<void> setAutoPlay(bool value) async =>
      _prefs.setBool(_kAutoPlay, value);

  double get speed => _prefs.getDouble(_kSpeed) ?? 1.0;
  Future<void> setSpeed(double value) async => _prefs.setDouble(_kSpeed, value);

  String get quality => _prefs.getString(_kQuality) ?? '高清';
  Future<void> setQuality(String value) async =>
      _prefs.setString(_kQuality, value);
}
