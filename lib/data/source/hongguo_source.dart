import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/drama.dart';
import 'drama_source.dart';

/// 为每次请求追加签名头（X-Gorgon / X-Argus 一类）。
typedef RequestSigner = Future<Map<String, String>> Function(Uri uri);

/// 红果站源。
///
/// 官方接口的每次请求都带设备指纹与签名参数，纯 Dart 客户端无法自行生成，
/// 所以这里把「签名」抽成可注入的 [signer]，并约定一层极简网关协议：
///
/// ```
/// GET {baseUrl}/feed?page=1&category=推荐
/// GET {baseUrl}/rank?type=hot&page=1
/// GET {baseUrl}/search?q=关键词&page=1
/// GET {baseUrl}/drama/{id}
/// GET {baseUrl}/drama/{id}/episodes
/// ```
///
/// 返回体统一为 `{"data": ...}` 或直接数组。你可以：
///
/// 1. 自建一个解析服务（真果鉴的做法：Go 核心负责签名与解析，Flutter 只做呈现）；
/// 2. 或者用系统 WebView 打开官方 H5，拦截页面自身发出的 XHR 响应（签名由官方页面完成）。
///
/// 两种方式都只需实现 [RequestSigner] 与网关，UI 层不用改一行。
class HongguoDramaSource implements DramaSource {
  HongguoDramaSource({required this.baseUrl, this.signer, this.headers = const {}});

  final String baseUrl;
  final RequestSigner? signer;
  final Map<String, String> headers;

  final _client = http.Client();
  static const _timeout = Duration(seconds: 12);

  @override
  String get id => 'hongguo';
  @override
  String get name => '红果';
  @override
  String get description => '官方通道 · 需配置签名器';
  @override
  bool get ready => baseUrl.trim().isNotEmpty;

  Uri _uri(String path, [Map<String, String>? query]) => Uri.parse(
        '${baseUrl.replaceAll(RegExp(r'/+$'), '')}$path',
      ).replace(queryParameters: query);

  Future<dynamic> _get(String path, [Map<String, String>? query]) async {
    if (!ready) {
      throw SourceException('红果站源尚未配置网关地址', kind: SourceErrorKind.unsupported);
    }
    final uri = _uri(path, query);
    final signed = signer == null ? const <String, String>{} : await signer!(uri);

    http.Response resp;
    try {
      resp = await _client.get(uri, headers: {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120.0 Mobile Safari/537.36',
        'Accept': 'application/json',
        ...headers,
        ...signed,
      }).timeout(_timeout);
    } catch (e) {
      throw SourceException('网络请求失败：$e');
    }

    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw SourceException('签名校验未通过（${resp.statusCode}）',
          kind: SourceErrorKind.auth);
    }
    if (resp.statusCode == 404) {
      throw SourceException('资源不存在', kind: SourceErrorKind.notFound);
    }
    if (resp.statusCode != 200) {
      throw SourceException('服务返回 ${resp.statusCode}');
    }
    if (resp.bodyBytes.isEmpty) {
      throw SourceException('响应为空，通常是缺少签名参数',
          kind: SourceErrorKind.auth);
    }

    final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
    if (decoded is Map<String, dynamic>) {
      return decoded['data'] ?? decoded['result'] ?? decoded['list'] ?? decoded;
    }
    return decoded;
  }

  List<Drama> _list(dynamic data) {
    final raw = data is List ? data : (data is Map ? data['list'] : null);
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map((e) => Drama.fromJson(e, source: 'hongguo'))
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
    final data = await _get('/drama/$dramaId');
    if (data is Map<String, dynamic>) {
      return Drama.fromJson(data, source: 'hongguo');
    }
    throw SourceException('详情数据格式异常');
  }

  @override
  Future<List<Episode>> fetchEpisodes(String dramaId) async {
    final data = await _get('/drama/$dramaId/episodes');
    final raw = data is List ? data : (data is Map ? data['list'] : null);
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(Episode.fromJson)
        .toList();
  }

  @override
  Future<List<String>> categories() async {
    try {
      final data = await _get('/categories');
      if (data is List) return data.map((e) => '$e').toList();
    } catch (_) {
      // 网关未实现该接口时回落到默认分类。
    }
    return const ['推荐', '都市', '甜宠', '逆袭', '古装', '悬疑', '萌宝'];
  }

  @override
  Future<void> dispose() async => _client.close();
}
