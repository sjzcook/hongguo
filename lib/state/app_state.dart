import 'package:flutter/foundation.dart';

import '../data/auth/auth_service.dart';
import '../data/local/local_store.dart';
import '../data/models/drama.dart';
import '../data/models/user_profile.dart';
import '../data/models/watch_progress.dart';
import '../data/source/demo_source.dart';
import '../data/source/drama_source.dart';
import '../data/source/hongguo_source.dart';

/// 全局状态：站源、收藏、观看历史、播放偏好、登录态。
///
/// 用最朴素的 [ChangeNotifier]，避免为一个客户端引入过重的状态框架。
class AppState extends ChangeNotifier {
  AppState(this._store)
      : _favorites = _store.favorites,
        _history = _store.history {
    _source = _buildSource(_store.sourceId);
    _auth = _buildAuthService();
    _authToken = _store.authToken;
    _profile = _store.authProfile;
  }

  final LocalStore _store;

  late DramaSource _source;
  late AuthService _auth;
  UserProfile? _profile;
  String? _authToken;
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

  /// 网关的 X-API-Key（部署脚本默认会生成一个）。
  static const hongguoToken = String.fromEnvironment(
    'HONGGUO_TOKEN',
    defaultValue: '',
  );

  DramaSource _buildSource(String id) {
    if (id == 'hongguo' && hongguoGateway.isNotEmpty) {
      return HongguoDramaSource(
        baseUrl: hongguoGateway,
        headers: {
          if (hongguoToken.isNotEmpty) 'X-API-Key': hongguoToken,
          if (_authToken != null) 'Authorization': 'Bearer $_authToken',
        },
      );
    }
    return DemoDramaSource();
  }

  /// 有网关就走网关认证，否则用完全离线的演示认证。
  AuthService _buildAuthService() {
    if (hongguoGateway.isNotEmpty) {
      return GatewayAuthService(
        baseUrl: hongguoGateway,
        apiKey: hongguoToken,
      );
    }
    return DemoAuthService();
  }

  // ---------------------------------------------------------------- 登录态

  bool get isLoggedIn => _profile != null && (_authToken?.isNotEmpty ?? false);

  UserProfile? get profile => _profile;

  /// 当前认证方式的展示名（演示模式 / 自建网关）。
  String get authLabel => _auth.label;

  String get authMode => _auth.mode;

  /// 登录页底部提示。
  String get authHint => _auth.hint;

  /// 该集是否可播：未标记付费，或已登录。
  bool canWatch(Episode episode) => !episode.locked || isLoggedIn;

  /// 发送验证码，返回调试用验证码（没有则为 null）。
  Future<String?> sendLoginCode(String phone) => _auth.sendCode(phone);

  /// 登录失败会抛出 [AuthException]，由页面捕获展示。
  Future<void> login({required String phone, required String code}) async {
    final session = await _auth.login(phone: phone, code: code);
    _authToken = session.token;
    _profile = session.profile;
    await _store.saveAuth(session.token, session.profile);
    await _rebuildSourceWithAuth();
    notifyListeners();
  }

  /// 用本地 token 复核一次账号信息，token 失效则自动登出。
  Future<void> refreshProfile() async {
    final token = _authToken;
    // 演示认证是纯本地的，没有服务端可复核。
    if (token == null || _auth.mode != 'gateway') return;
    try {
      final fresh = await _auth.fetchProfile(token);
      _profile = fresh;
      await _store.saveAuth(token, fresh);
      notifyListeners();
    } on AuthException catch (e) {
      if (e.kind == AuthErrorKind.invalid) await logout();
    } catch (_) {
      // 网络问题不影响已登录状态，保留本地缓存。
    }
  }

  Future<void> logout() async {
    final token = _authToken;
    _authToken = null;
    _profile = null;
    await _store.clearAuth();
    if (token != null) await _auth.logout(token);
    await _rebuildSourceWithAuth();
    notifyListeners();
  }

  Future<void> _rebuildSourceWithAuth() async {
    await _source.dispose();
    _source = _buildSource(_store.sourceId);
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
    _auth.dispose();
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
