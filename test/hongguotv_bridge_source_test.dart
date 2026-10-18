import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hongguo/data/source/hongguotv_bridge_source.dart';

void main() {
  group('HongguoTvBridgeSource', () {
    test('maps documented home/search/series schema and authenticated stream URL', () async {
      final requests = <http.Request>[];
      final source = HongguoTvBridgeSource(
        baseUrl: 'https://bridge.example.test',
        token: 'test-token',
        client: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/api/home' ||
              request.url.path == '/api/search') {
            return http.Response(
              jsonEncode({
                'items': [
                  {
                    'id': 'series-1',
                    'title': '桥接测试剧',
                    'cover': 'https://media.example.test/cover.jpg',
                    'tags': ['都市'],
                  }
                ],
                'page': 1,
              }),
              200,
            );
          }
          if (request.url.path == '/api/series/series-1') {
            return http.Response(
              jsonEncode({
                'id': 'series-1',
                'title': '桥接测试剧',
                'episodes': [
                  {'id': 'episode-2', 'number': 2, 'title': '第二集'},
                  {'id': 'episode-1', 'number': 1, 'title': '第一集'},
                ],
              }),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      );

      final feed = await source.fetchFeed();
      expect(feed.single.title, '桥接测试剧');

      final search = await source.search('测试');
      expect(search.single.id, 'series-1');
      expect(requests[1].url.queryParameters['q'], '测试');

      final detail = await source.fetchDetail('series-1');
      expect(detail.title, '桥接测试剧');

      final episodes = await source.fetchEpisodes('series-1');
      expect(episodes.map((episode) => episode.index), [1, 2]);
      expect(
        episodes.first.videoUrl,
        'https://bridge.example.test/api/episodes/episode-1/stream',
      );
      expect(episodes.first.httpHeaders['Authorization'], 'Bearer test-token');
      expect(requests.first.headers['Authorization'], 'Bearer test-token');

      await source.dispose();
    });

    test('does not pretend unsupported ranking routes exist', () async {
      final source = HongguoTvBridgeSource(
        baseUrl: 'https://bridge.example.test',
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      expect(
        () => source.fetchRanking(RankingType.hot),
        throwsA(isA<SourceException>()),
      );
      await source.dispose();
    });
  });
}
