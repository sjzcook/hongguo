import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hongguo/data/models/drama.dart';
import 'package:hongguo/data/source/demo_source.dart';
import 'package:hongguo/widgets/drama_card.dart';

void main() {
  group('DemoDramaSource', () {
    late DemoDramaSource source;

    setUp(() => source = DemoDramaSource());

    test('推荐流按页返回，且不超过页大小', () async {
      final first = await source.fetchFeed(page: 1);
      expect(first, isNotEmpty);
      expect(first.length, lessThanOrEqualTo(18));
    });

    test('排行榜按类型筛选', () async {
      final completed = await source.fetchRanking(RankingType.finished);
      expect(completed.every((d) => d.isCompleted), isTrue);

      final hot = await source.fetchRanking(RankingType.hot);
      for (var i = 1; i < hot.length; i++) {
        expect(hot[i - 1].playCount >= hot[i].playCount, isTrue);
      }
    });

    test('搜索命中标题与标签', () async {
      final byTitle = await source.search('龙王');
      expect(byTitle, isNotEmpty);
      expect(byTitle.first.title.contains('龙王'), isTrue);

      final empty = await source.search('不存在的剧名xyz');
      expect(empty, isEmpty);
    });

    test('详情与选集数量一致', () async {
      final feed = await source.fetchFeed(page: 1);
      final drama = feed.first;
      final detail = await source.fetchDetail(drama.id);
      final episodes = await source.fetchEpisodes(drama.id);

      expect(detail.id, drama.id);
      expect(episodes.length, detail.availableEpisodes);
      expect(episodes.first.index, 1);
      expect(episodes.first.videoUrl, isNotEmpty);
    });

    test('未知剧集抛出 SourceException', () async {
      expect(
        () => source.fetchDetail('not-exist'),
        throwsA(isA<Exception>()),
      );
    });
  });

  testWidgets('剧卡渲染标题与集数', (tester) async {
    const drama = Drama(
      id: 't1',
      title: '测试剧名',
      totalEpisodes: 40,
      updatedEpisodes: 12,
      score: 9.1,
    );

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 120,
          height: 220,
          child: DramaPosterCard(drama: drama),
        ),
      ),
    ));

    expect(find.text('测试剧名'), findsOneWidget);
    expect(find.text('更新至 12 集'), findsOneWidget);
  });
}
