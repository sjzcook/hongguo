import '../models/drama.dart';

/// 站源抽象。
///
/// 真果鉴把站源请求、解析放在 Go 核心层（FFI）里，本项目的思路一致：
/// UI 只依赖这层接口，具体站源可替换、可并联，互不影响。
///
/// 内置实现：
/// * [DemoDramaSource]  —— 离线演示数据，保证 UI 与播放链路随开随用；
/// * [HongguoDramaSource] —— 红果官方通道，请求经可注入的签名器发出。
abstract class DramaSource {
  String get id;
  String get name;
  String get description;

  /// 是否已完成配置（演示源恒为 true）。
  bool get ready;

  Future<List<Drama>> fetchFeed({int page = 1, String? category});

  Future<List<Drama>> fetchRanking(RankingType type, {int page = 1});

  Future<List<Drama>> search(String keyword, {int page = 1});

  Future<Drama> fetchDetail(String dramaId);

  Future<List<Episode>> fetchEpisodes(String dramaId);

  Future<List<String>> categories();

  Future<void> dispose() async {}
}

/// 站源不可用或请求失败时抛出，UI 据此展示重试态。
class SourceException implements Exception {
  SourceException(this.message, {this.kind = SourceErrorKind.network});

  final String message;
  final SourceErrorKind kind;

  @override
  String toString() => message;
}

enum SourceErrorKind { network, auth, notFound, unsupported }
