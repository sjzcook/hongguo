import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/drama.dart';
import 'drama_source.dart';

/// 适配 N3urda/hongguoTV 文档化的家庭网关 API v1。
///
/// 只使用网关公开的 /api/home、/api/search、/api/series/:id 和
/// /api/episodes/:id/stream 契约。不会自行请求平台私有 API，也不解密媒体。
class HongguoTvBridgeSource implements DramaSource {
  HongguoTvBridgeSource({
    required this.baseUrl,
    this.token = '',
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final String token;
  final http.Client _client;
  static const _timeout = Duration(seconds: 15);

  @override
  String get id => 'hongguo';
  @override
  String get name => '红果 TV 第三方网关';
  @override
  String get description => 'hongguoTV API v1 · 需自建网关';
  @override
  bool get ready => baseUrl.trim().isNotEmpty;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(baseUrl.trim());
    final normalizedPath =
        '${base.path.replaceAll(RegExp(r'/+$'), '')}/${path.replaceFirst(RegExp(r'^/+'), '')}';
    return base.replace(path: normalizedPath, queryParameters: query);
  }

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        if (token.trim().isNotEmpty) 'Authorization': 'Bearer ${token.trim()}',
      };

  Future<dynamic> _getJson(String path, [Map<String, String>? query]) async {
    if (!ready) {
      throw SourceException('尚未配置第三方网关地址',
          kind: SourceErrorKind.unsupported);
    }
    final uri = _uri(path, query);
    late http.Response response;
    try {
      response = await _client.get(uri, headers: _headers).timeout(_timeout);
    } catch (error) {
      throw SourceException('第三方网关请求失败：$error');
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw SourceException('第三方网关认证失败（${response.statusCode}）',
          kind: SourceErrorKind.auth);
    }
    if (response.statusCode == 404) {
      throw SourceException('剧集或分集不存在', kind: SourceErrorKind.notFound);
    }
    if (response.statusCode != 200) {
      var message = '第三方网关返回 ${response.statusCode}';
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['error'] != null) {
          message = '${body['error']}';
        }
      } catch (_) {
        // 使用 HTTP 状态码作为安全的兜底提示。
      }
      throw SourceException(message);
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw SourceException('第三方网关未返回有效 JSON');
    }
  }

  dynamic _unwrap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value['data'] ?? value['result'] ?? value;
    }
    return value;
  }

  List<Drama> _parseSeries(dynamic value) {
    final data = _unwrap(value);
    final list = data is List
        ? data
        : data is Map
            ? (data['items'] ?? data['list'] ?? data['results'])
            : null;
    if (list is! List) return const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map((item) => Drama.fromJson(item, source: 'hongguo'))
        .where((item) => item.id.isNotEmpty)
        .toList();
  }

  @override
  Future<List<Drama>> fetchFeed({int page = 1, String? category}) async {
    final items = _parseSeries(await _getJson('/api/home', {'page': '$page'}));
    if (category == null || category.isEmpty || category == '推荐') {
      return items;
    }
    return items.where((item) =>
        item.category == category || item.tags.contains(category)).toList();
  }

  @override
  Future<List<Drama>> fetchRanking(RankingType type, {int page = 1}) async {
    // API v1 未提供排行榜路由；不伪造榜单数据。
    throw SourceException('当前第三方网关 API v1 未提供排行榜接口',
        kind: SourceErrorKind.unsupported);
  }

  @override
  Future<List<Drama>> search(String keyword, {int page = 1}) async {
    if (keyword.trim().isEmpty) return const [];
    return _parseSeries(await _getJson('/api/search', {
      'q': keyword.trim(),
      'page': '$page',
    }));
  }

  @override
  Future<Drama> fetchDetail(String dramaId) async {
    final data = _unwrap(await _getJson(
      '/api/series/${Uri.encodeComponent(dramaId)}',
    ));
    if (data is Map<String, dynamic>) {
      final drama = Drama.fromJson(data, source: 'hongguo');
      if (drama.id.isNotEmpty) return drama;
    }
    throw SourceException('第三方网关详情格式异常');
  }

  @override
  Future<List<Episode>> fetchEpisodes(String dramaId) async {
    final data = _unwrap(await _getJson(
      '/api/series/${Uri.encodeComponent(dramaId)}',
    ));
    final raw = data is Map ? data['episodes'] : null;
    if (raw is! List) {
      throw SourceException('第三方网关详情未返回分集列表',
          kind: SourceErrorKind.unsupported);
    }
    final streamHeaders = {
      if (token.trim().isNotEmpty) 'Authorization': 'Bearer ${token.trim()}',
    };
    final episodes = raw.whereType<Map<String, dynamic>>().map((json) {
      final parsed = Episode.fromJson(json);
      if (parsed.id.isEmpty) {
        return parsed;
      }
      final streamPath =
          '/api/episodes/${Uri.encodeComponent(parsed.id)}/stream';
      return Episode(
        id: parsed.id,
        index: parsed.index,
        title: parsed.title,
        videoUrl: _uri(streamPath).toString(),
        duration: parsed.duration,
        locked: parsed.locked,
        httpHeaders: streamHeaders,
      );
    }).toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    return episodes;
  }

  @override
  Future<List<String>> categories() async =>
      const ['推荐', '都市', '甜宠', '逆袭', '古装', '悬疑', '萌宝'];

  @override
  Future<void> dispose() async => _client.close();
}
