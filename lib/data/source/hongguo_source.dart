import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/drama.dart';
import 'drama_source.dart';
import 'hongguo_gateway_config.dart';

/// Third-party metadata gateway plus the playback resolver configured by
/// MiniReel's sources.json.
///
/// The metadata gateway is still supplied by HONGGUO_GATEWAY and must implement
/// /feed, /rank, /search, /drama/{id}, and /drama/{id}/episodes. If an episode
/// has no direct video URL but includes an episode number, this source asks the
/// configured playback endpoint for a short-lived authorized playback URL.
typedef RequestSigner = Future<Map<String, String>> Function(Uri uri);

class HongguoDramaSource implements DramaSource {
  HongguoDramaSource({
    required this.baseUrl,
    this.playbackEndpoint = HongguoGatewayConfig.playbackEndpoint,
    this.signer,
    this.headers = const {},
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final String playbackEndpoint;
  final RequestSigner? signer;
  final Map<String, String> headers;
  final http.Client _client;

  Duration get _timeout =>
      Duration(seconds: HongguoGatewayConfig.timeoutSeconds);

  @override
  String get id => 'hongguo';
  @override
  String get name => '红果';
  @override
  String get description => '红果网关 + 配置的播放解析接口';
  @override
  bool get ready => baseUrl.trim().isNotEmpty;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(baseUrl.trim());
    final normalizedPath =
        '${base.path.replaceAll(RegExp(r'/+$'), '')}/${path.replaceFirst(RegExp(r'^/+'), '')}';
    return base.replace(path: normalizedPath, queryParameters: query);
  }

  Future<dynamic> _decodeResponse(http.Response response) async {
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw SourceException('网关认证失败（${response.statusCode}）',
          kind: SourceErrorKind.auth);
    }
    if (response.statusCode == 404) {
      throw SourceException('资源不存在', kind: SourceErrorKind.notFound);
    }
    if (response.statusCode != 200) {
      throw SourceException('服务返回 ${response.statusCode}');
    }
    if (response.bodyBytes.isEmpty) throw SourceException('服务响应为空');

    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw SourceException('服务未返回有效 JSON');
    }
    if (decoded is Map<String, dynamic>) {
      return decoded['data'] ?? decoded['result'] ?? decoded['list'] ?? decoded;
    }
    return decoded;
  }

  Future<dynamic> _get(String path, [Map<String, String>? query]) async {
    if (!ready) {
      throw SourceException('尚未配置红果元数据网关地址',
          kind: SourceErrorKind.unsupported);
    }
    final uri = _uri(path, query);
    final signed = signer == null ? const <String, String>{} : await signer!(uri);

    try {
      final response = await _client.get(uri, headers: {
        'Accept': 'application/json',
        'Referer': HongguoGatewayConfig.referer,
        ...headers,
        ...signed,
      }).timeout(_timeout);
      return await _decodeResponse(response);
    } on SourceException {
      rethrow;
    } catch (e) {
      throw SourceException('网络请求失败：$e');
    }
  }

  List<Drama> _list(dynamic data) {
    final raw = data is List
        ? data
        : (data is Map
            ? (data['list'] ?? data['items'] ?? data['results'])
            : null);
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map((e) => Drama.fromJson(e, source: 'hongguo'))
        .where((drama) => drama.id.isNotEmpty)
        .toList();
  }

  @override
  Future<List<Drama>> fetchFeed({int page = 1, String? category}) async {
    final data = await _get('/feed', {
      'page': '$page',
      if (category != null && category.isNotEmpty) 'category': category,
    });
    return _list(data);
  }

  @override
  Future<List<Drama>> fetchRanking(RankingType type, {int page = 1}) async {
    final data = await _get('/rank', {'type': type.slug, 'page': '$page'});
    return _list(data);
  }

  @override
  Future<List<Drama>> search(String keyword, {int page = 1}) async {
    if (keyword.trim().isEmpty) return const [];
    final data = await _get('/search', {'q': keyword.trim(), 'page': '$page'});
    return _list(data);
  }

  @override
  Future<Drama> fetchDetail(String dramaId) async {
    final data = await _get('/drama/${Uri.encodeComponent(dramaId)}');
    if (data is Map<String, dynamic>) {
      final drama = Drama.fromJson(data, source: 'hongguo');
      if (drama.id.isNotEmpty) return drama;
    }
    throw SourceException('详情数据格式异常');
  }

  Future<String> _resolvePlayback({
    required String dramaId,
    required int episodeNumber,
  }) async {
    final endpoint = playbackEndpoint.trim();
    if (endpoint.isEmpty) return '';
    final uri = Uri.parse(endpoint).replace(queryParameters: {
      ...Uri.parse(endpoint).queryParameters,
      'series_id': dramaId,
      'ep': '$episodeNumber',
    });

    Object? lastError;
    for (var attempt = 0; attempt < HongguoGatewayConfig.retries; attempt++) {
      try {
        final response = await _client.get(uri, headers: {
          'Accept': 'application/json',
          'Referer': HongguoGatewayConfig.referer,
          ...headers,
        }).timeout(_timeout);
        if (response.statusCode != 200) {
          lastError = 'HTTP ${response.statusCode}';
          continue;
        }
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        final payload = decoded is Map<String, dynamic>
            ? (decoded['data'] ?? decoded['result'] ?? decoded)
            : decoded;
        if (payload is Map) {
          final url = '${payload['url'] ?? payload['video_url'] ?? payload['play_url'] ?? ''}'.trim();
          if (url.startsWith('https://') || url.startsWith('http://')) {
            return url;
          }
          lastError = payload['message'] ?? payload['msg'] ?? '响应中没有播放地址';
        } else {
          lastError = '播放接口响应格式异常';
        }
      } catch (e) {
        lastError = e;
      }
    }
    throw SourceException('播放地址解析失败：$lastError');
  }

  @override
  Future<List<Episode>> fetchEpisodes(String dramaId) async {
    final data = await _get(
        '/drama/${Uri.encodeComponent(dramaId)}/episodes');
    final raw = data is List
        ? data
        : (data is Map
            ? (data['list'] ?? data['episodes'] ?? data['items'])
            : null);
    if (raw is! List) return const [];

    final episodes = <Episode>[];
    for (final item in raw.whereType<Map<String, dynamic>>()) {
      final index = int.tryParse('${item['index'] ?? item['ep'] ?? item['episode'] ?? 1}') ?? 1;
      var episode = Episode.fromJson(item);
      if (episode.videoUrl.isEmpty &&
          item['playable'] != false &&
          index > 0) {
        try {
          final url = await _resolvePlayback(
            dramaId: dramaId,
            episodeNumber: index,
          );
          episode = Episode(
            index: index,
            title: episode.title,
            videoUrl: url,
            duration: episode.duration,
            locked: episode.locked,
          );
        } on SourceException {
          // Preserve the episode entry even when the resolver is temporarily
          // unavailable; the UI can show it and retry on a later request.
        }
      }
      episodes.add(episode);
    }
    episodes.sort((a, b) => a.index.compareTo(b.index));
    return episodes;
  }

  @override
  Future<List<String>> categories() async {
    try {
      final data = await _get('/categories');
      if (data is List) {
        return data
            .map((item) => item is Map
                ? '${item['name'] ?? item['title'] ?? ''}'
                : '$item')
            .where((name) => name.isNotEmpty)
            .toList();
      }
    } catch (_) {
      // Optional endpoint; use built-in categories if the gateway omits it.
    }
    return const ['推荐', '都市', '甜宠', '逆袭', '古装', '悬疑', '萌宝'];
  }

  @override
  Future<void> dispose() async => _client.close();
}
