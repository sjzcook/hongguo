import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hongguo/data/source/hongguo_gateway_config.dart';
import 'package:hongguo/data/source/hongguo_source.dart';

void main() {
  test('keeps gateway values from MiniReel sources.json', () {
    expect(HongguoGatewayConfig.websiteBaseUrl, 'https://hongguoduanju.com');
    expect(
      HongguoGatewayConfig.playbackEndpoint,
      'https://djapi.999888456.xyz/api/hongguo/play',
    );
    expect(HongguoGatewayConfig.pageSize, 24);
    expect(HongguoGatewayConfig.timeoutSeconds, 12);
  });

  test('resolves episode URL using series_id and ep query parameters', () async {
    final requests = <Uri>[];
    final source = HongguoDramaSource(
      baseUrl: 'https://metadata.example.test',
      playbackEndpoint: 'https://play.example.test/api/hongguo/play',
      client: MockClient((request) async {
        requests.add(request.url);
        if (request.url.path.endsWith('/episodes')) {
          return http.Response(
            jsonEncode({
              'data': {
                'episodes': [
                  {
                    'ep': 2,
                    'episode_id': 'ep-2',
                    'episode_title': '第二集',
                    'playable': true,
                  }
                ]
              }
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path.endsWith('/play')) {
          return http.Response(
            jsonEncode({
              'code': 10000,
              'data': {
                'series_id': request.url.queryParameters['series_id'],
                'ep': int.parse(request.url.queryParameters['ep']!),
                'playable': true,
                'url': 'https://media.example.test/episode-2.mp4',
              }
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 404);
      }),
    );
    addTearDown(source.dispose);

    final episodes = await source.fetchEpisodes('series-123');

    expect(episodes, hasLength(1));
    expect(episodes.single.index, 2);
    expect(episodes.single.title, '第二集');
    expect(
      episodes.single.videoUrl,
      'https://media.example.test/episode-2.mp4',
    );
    final playRequest = requests.singleWhere((uri) => uri.path.endsWith('/play'));
    expect(playRequest.queryParameters['series_id'], 'series-123');
    expect(playRequest.queryParameters['ep'], '2');
  });
}
