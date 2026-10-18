import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hongguo/data/source/hongguo_source.dart';

void main() {
  group('HongguoDramaSource third-party gateway adapter', () {
    late List<Uri> requests;
    late HongguoDramaSource source;

    setUp(() {
      requests = [];
      source = HongguoDramaSource(
        baseUrl: 'https://gateway.example.test/api',
        client: MockClient((request) async {
          requests.add(request.url);
          final path = request.url.path;
          if (path.endsWith('/feed')) {
            return http.Response(
              jsonEncode({
                'data': {
                  'list': [
                    {
                      'series_id': 'series-1',
                      'series_title': '测试短剧',
                      'cover_url': 'https://media.example.test/cover.jpg',
                      'total': 3,
                      'desc': '测试简介'
                    }
                  ]
                }
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (path.endsWith('/drama/series-1')) {
            return http.Response(
              jsonEncode({
                'data': {
                  'series_id': 'series-1',
                  'series_title': '测试短剧',
                  'total': 3
                }
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (path.endsWith('/episodes')) {
            return http.Response(
              jsonEncode({
                'data': {
                  'episodes': [
                    {
                      'vid_index': 2,
                      'episode_title': '第二集',
                      'play_url': 'https://media.example.test/ep2.mp4',
                      'duration_seconds': 60
                    },
                    {
                      'vid_index': 1,
                      'episode_title': '第一集',
                      'play_url': 'https://media.example.test/ep1.mp4',
                      'duration_seconds': 45,
                      'is_locked': true
                    }
                  ]
                }
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('{}', 404);
        }),
      );
    });

    tearDown(() => source.dispose());

    test('maps third-party series fields into Drama', () async {
      final dramas = await source.fetchFeed(page: 1, category: '都市');

      expect(dramas, hasLength(1));
      expect(dramas.single.id, 'series-1');
      expect(dramas.single.title, '测试短剧');
      expect(dramas.single.totalEpisodes, 3);
      expect(dramas.single.cover, 'https://media.example.test/cover.jpg');
      expect(requests.single.queryParameters['category'], '都市');
      expect(requests.single.queryParameters['page'], '1');
    });

    test('maps and sorts episode fields and direct playback URLs', () async {
      final episodes = await source.fetchEpisodes('series-1');

      expect(episodes.map((e) => e.index), [1, 2]);
      expect(episodes.first.title, '第一集');
      expect(episodes.first.videoUrl, 'https://media.example.test/ep1.mp4');
      expect(episodes.first.locked, isTrue);
      expect(episodes.first.duration, const Duration(seconds: 45));
      expect(episodes.last.videoUrl, 'https://media.example.test/ep2.mp4');
    });

    test('maps series detail using series_id alias', () async {
      final detail = await source.fetchDetail('series-1');
      expect(detail.id, 'series-1');
      expect(detail.title, '测试短剧');
    });

    test('rejects invalid JSON with a useful error', () async {
      final invalidSource = HongguoDramaSource(
        baseUrl: 'https://gateway.example.test',
        client: MockClient((_) async => http.Response('not-json', 200)),
      );
      expect(
        () => invalidSource.fetchFeed(),
        throwsA(isA<Exception>()),
      );
      await invalidSource.dispose();
    });
  });
}
