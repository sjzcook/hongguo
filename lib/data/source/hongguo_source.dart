import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/drama.dart';
import 'drama_source.dart';

/// 可注入请求头的第三方网关站源。
///
/// 此客户端只调用项目定义的网关契约，不直接模拟红果 App 的设备指纹、
/// 私有签名或加密媒体协议。网关应只返回调用方有权访问的元数据，以及
/// 播放器可直接播放且获得授权的媒体 URL。
///
/// GET {baseUrl}/feed?page=1&category=推荐
/// GET {baseUrl}/rank?type=hot&page=1
/// GET {baseUrl}/search?q=关键词&page=1
/// GET {baseUrl}/drama/{id}
/// GET {baseUrl}/drama/{id}/episodes
///
/// 响应可以使用 {"data": ...}、{"result": ...}、{"list": ...} 包装，
/// 具体字段由 Drama.fromJson / Episode.fromJson 统一兼容。
typedef RequestSigner = Future<Map<String, String>> Function(Uri uri);

class HongguoDramaSource implements DramaSource {
  HongguoDramaSource({
    required this.baseUrl,
    this.signer,
    this.headers = const {},
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final RequestSigner? signer;
  final Map<String, String> headers;
  final http.Client _client;
  static const _timeout = Duration(seconds: 12);

  @override
  String get id => 'hongguo';
  @override
  String get name => '第三方红果网关';
  @override
  String get description => '第三方接口 · 需配置网关服务';
  @override
  bool get ready => baseUrl.trim().isNotEmpty;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(baseUrl.trim());
    final normalizedPath = '${base.path.replaceAll(RegExp(r'/+$'), '')}/${path.replaceFirst(RegExp(r'^/+'), '')}';
    return base.replace(path: normalizedPath, queryParameters: query);
  }

  Future<dynamic> _get(String path, [Map<String, String>? query]) async {
    if (!ready) {
      throw SourceException('第三方站源尚未配置网关地址',
          kind: SourceErrorKind.unsupported);
    }
    final uri = _uri(path, query);
    final signed = signer == null ? const <String, String>{} : await signer!(uri);

    http.Response resp;
    try {
      resp = await _client.get(uri, headers: {
        'Accept': 'application/json',
        ...headers,
        ...signed,
      }).timeout(_timeout);
    } catch (e) {
      throw SourceException('网络请求失败：$e');
    }

    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw SourceException('网关认证失败（${resp.statusCode}）',
          kind: SourceErrorKind.auth);
    }
    if (resp.statusCode == 404) {
      throw SourceException('资源不存在', kind: SourceErrorKind.notFound);
    }
    if (resp.statusCode != 200) {
      throw SourceException('服务返回 ${resp.statusCode}');
    }
    if (resp.bodyBytes.isEmpty) {
      throw SourceException('服务响应为空');
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(resp.bodyBytes));
    } on FormatException {
      throw SourceException('服务未返回有效 JSON');
    }
    if (decoded is Map<String, dynamic>) {
      return decoded['data'] ?? decoded['result'] ?? decoded['list'] ?? decoded;
    }
    return decoded;
  }

  List<Drama> _list(dynamic data) {
    final raw = data is List ? data : (data is Map ? (data['list'] ?? data['items'] ?? data['results']) : null);
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

  @override
  Future<List<Episode>> fetchEpisodes(String dramaId) async {
    final data = await _get('/drama/${Uri.encodeComponent(dramaId)}/episodes');
    final raw = data is List ? data : (data is Map ? (data['list'] ?? data['episodes'] ?? data['items']) : null);
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(Episode.fromJson)
        .toList()
      ..sort((a, b) => a.index.compareTo(b.index));
  }

  @override
  Future<List<String>> categories() async {
    try {
      final data = await _get('/categories');
      if (data is List) {
        return data
            .map((item) => item is Map ? '${item['name'] ?? item['title'] ?? ''}' : '$item')
            .where((name) => name.isNotEmpty)
            .toList();
      }
    } catch (_) {
      // 网关未实现该可选接口时使用默认分类。
    }
    return const ['推荐', '都市', '甜宠', '逆袭', '古装', '悬疑', '萌宝'];
  }

  @override
  Future<void> dispose() async => _client.close();
}
