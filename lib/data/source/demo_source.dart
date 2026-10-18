import 'dart:math';

import '../models/drama.dart';
import 'drama_source.dart';

/// 内置演示站源。
///
/// 不依赖任何外部接口，用于验证 UI、播放、收藏与续播全链路。
/// 换真实站源时只需实现 [DramaSource]，UI 无需改动。
class DemoDramaSource implements DramaSource {
  DemoDramaSource();

  @override
  String get id => 'demo';
  @override
  String get name => '演示站源';
  @override
  String get description => '内置离线剧库，用于预览与调试';
  @override
  bool get ready => true;

  static const _pageSize = 9;

  /// 公开示例视频，演示播放链路用。
  static const _demoVideos = [
    'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
    'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4',
  ];

  late final List<Drama> _library = _seedLibrary();

  @override
  Future<List<Drama>> fetchFeed({int page = 1, String? category}) async {
    await Future<void>.delayed(const Duration(milliseconds: 260));
    var list = _library;
    if (category != null && category.isNotEmpty && category != '推荐') {
      list = list.where((d) => d.category == category).toList();
    }
    return _paginate(list, page, pageSize: _pageSize * 2);
  }

  @override
  Future<List<Drama>> fetchRanking(RankingType type, {int page = 1}) async {
    await Future<void>.delayed(const Duration(milliseconds: 220));
    final list = switch (type) {
      RankingType.hot => [..._library]..sort((a, b) => b.playCount - a.playCount),
      RankingType.newest => [..._library]..sort((a, b) => b.id.compareTo(a.id)),
      RankingType.finished => _library.where((d) => d.isCompleted).toList(),
      RankingType.ai => _library.where((d) => d.tags.contains('漫剧')).toList(),
    };
    return _paginate(list, page, pageSize: _pageSize);
  }

  @override
  Future<List<Drama>> search(String keyword, {int page = 1}) async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    final q = keyword.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final list = _library.where((d) {
      return d.title.toLowerCase().contains(q) ||
          d.description.toLowerCase().contains(q) ||
          d.category.toLowerCase().contains(q) ||
          d.actors.any((a) => a.toLowerCase().contains(q)) ||
          d.tags.any((t) => t.toLowerCase().contains(q));
    }).toList();
    return _paginate(list, page, pageSize: _pageSize);
  }

  @override
  Future<Drama> fetchDetail(String dramaId) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    for (final d in _library) {
      if (d.id == dramaId) return d;
    }
    throw SourceException('未找到该剧', kind: SourceErrorKind.notFound);
  }

  /// 演示源同样遵守「前 N 集免费」的产品规则，方便验证登录门禁。
  static const freeEpisodes = 8;

  @override
  Future<List<Episode>> fetchEpisodes(String dramaId) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final drama = await fetchDetail(dramaId);
    final count = drama.availableEpisodes;
    return List.generate(count, (i) {
      final index = i + 1;
      return Episode(
        index: index,
        title: '第 $index 集',
        videoUrl: _demoVideos[(int.parse(drama.id.replaceAll(RegExp(r'\D'), '')) + i) %
            _demoVideos.length],
        duration: Duration(seconds: 45 + (i * 13) % 60),
        locked: index > freeEpisodes,
      );
    });
  }

  @override
  Future<List<String>> categories() async => const [
        '推荐',
        '都市',
        '甜宠',
        '逆袭',
        '古装',
        '悬疑',
        '萌宝',
        '年代',
        '玄幻',
      ];

  @override
  Future<void> dispose() async {}

  List<Drama> _paginate(List<Drama> list, int page, {required int pageSize}) {
    final start = (page - 1) * pageSize;
    if (start >= list.length) return const [];
    return list.sublist(start, min(start + pageSize, list.length));
  }

  List<Drama> _seedLibrary() {
    const seeds = <List<Object>>[
      [
        '龙王归来',
        '都市',
        '五年前他被逐出家门，五年后他带着一身荣耀归来。当年看不起他的人，如今跪在面前瑟瑟发抖。',
        ['逆袭', '战神', '打脸'],
        ['陈默', '苏晚晴'],
        72,
        72,
        DramaStatus.completed,
        328600000,
        9.2,
      ],
      [
        '闪婚后，傅总马甲藏不住了',
        '甜宠',
        '闪婚三天，她发现丈夫竟是集团总裁。本想低调过日子，谁知道他的马甲一个比一个掉得快。',
        ['甜宠', '豪门', '先婚后爱'],
        ['林晚', '傅时衍'],
        68,
        51,
        DramaStatus.ongoing,
        215400000,
        9.0,
      ],
      [
        '重生八零：我靠空间发家',
        '年代',
        '一朝重生回到 1983 年，随身空间在手，她要把上辈子错过的全都拿回来。',
        ['重生', '空间', '年代'],
        ['苏锦', '陆铮'],
        88,
        88,
        DramaStatus.completed,
        176200000,
        9.1,
      ],
      [
        '赘婿的逆袭人生',
        '逆袭',
        '当了三年上门女婿，所有人都当他是废物。直到他重新拿起那枚家族徽章。',
        ['逆袭', '赘婿', '热血'],
        ['秦风', '柳如烟'],
        64,
        40,
        DramaStatus.ongoing,
        154300000,
        8.8,
      ],
      [
        '总裁的替身新娘',
        '甜宠',
        '她只是替身，却动了真心。当正主归来那天，她收拾好行李，只留一句"恭喜"。',
        ['替身', '虐恋', '追妻'],
        ['温柔', '顾言深'],
        56,
        56,
        DramaStatus.completed,
        132700000,
        8.9,
      ],
      [
        '穿越之我是女帝',
        '古装',
        '现代女法医穿越成冷宫弃妃，开局一杯毒酒，她反手把毒药换成了补药。',
        ['穿越', '女强', '权谋'],
        ['沈知意', '萧景珩'],
        92,
        75,
        DramaStatus.ongoing,
        121900000,
        9.3,
      ],
      [
        '萌宝驾到：爹地快投降',
        '萌宝',
        '五年前她带球跑路，五年后两个小包子把亲爹堵在了公司门口："签个字，不然我们不走了。"',
        ['萌宝', '团宠', '甜宠'],
        ['夏小满', '霍云深'],
        60,
        60,
        DramaStatus.completed,
        118500000,
        8.7,
      ],
      [
        '离婚后，前妻跪求复合',
        '都市',
        '签字那天她笑得云淡风轻。三个月后，她站在他面前红着眼说"我后悔了"。',
        ['虐恋', '追妻火葬场'],
        ['许知微', '陆时晏'],
        48,
        33,
        DramaStatus.ongoing,
        96700000,
        8.5,
      ],
      [
        '神医下山',
        '玄幻',
        '师父让他下山娶个媳妇，结果一下山就撞上了满城风雨的豪门恩怨。',
        ['神医', '玄学', '爽文'],
        ['叶尘', '苏若雪'],
        76,
        76,
        DramaStatus.completed,
        89300000,
        8.6,
      ],
      [
        '我在民国当大佬',
        '年代',
        '穿到 1927 年的上海滩，他兜里只有一块大洋，但脑子里有一整个时代。',
        ['穿越', '民国', '商战'],
        ['周砚', '沈曼卿'],
        58,
        44,
        DramaStatus.ongoing,
        82100000,
        9.0,
      ],
      [
        '隐婚总裁的小娇妻',
        '甜宠',
        '结婚一年，公司里没人知道她丈夫是谁。直到年会那天，他牵着她走上了台。',
        ['隐婚', '甜宠', '宠妻'],
        ['南乔', '厉行舟'],
        52,
        52,
        DramaStatus.completed,
        76400000,
        8.4,
      ],
      [
        '天降三宝：妈咪别跑',
        '萌宝',
        '一胎三宝，个个天才。大宝搞代码，二宝搞金融，三宝专门搞亲爹。',
        ['萌宝', '团宠', '天才宝宝'],
        ['林一一', '盛亦川'],
        66,
        66,
        DramaStatus.completed,
        71200000,
        8.6,
      ],
      [
        '校花的贴身高手',
        '都市',
        '转学生第一天就被校花盯上了，理由很简单——他能打，还不要钱。',
        ['校园', '热血', '护花'],
        ['李闲', '楚梦瑶'],
        70,
        29,
        DramaStatus.ongoing,
        65800000,
        8.2,
      ],
      [
        '她的秘密',
        '悬疑',
        '丈夫每晚十点准时出门，她跟了三个月，终于在那栋旧楼里看见了另一个自己。',
        ['悬疑', '反转', '烧脑'],
        ['姜宁', '周维'],
        42,
        42,
        DramaStatus.completed,
        58300000,
        9.4,
      ],
      [
        '豪门弃女归来',
        '逆袭',
        '被赶出家门那天，她只带走了一本账。十年后，那本账让整个家族跪着求她回来。',
        ['复仇', '豪门', '女强'],
        ['傅晚宁', '谢允'],
        62,
        48,
        DramaStatus.ongoing,
        54700000,
        8.8,
      ],
      [
        '我在天庭当保安',
        '玄幻',
        '应聘天庭保安第一天，他拦下了闯南天门的孙悟空，还被评了月度优秀员工。',
        ['玄幻', '搞笑', '漫剧'],
        ['张小凡', '嫦小娥'],
        54,
        54,
        DramaStatus.completed,
        49200000,
        8.9,
      ],
      [
        '首富从捡漏开始',
        '都市',
        '地摊上十块钱买的破碗，转手拍出八千万。他的眼睛，能看见别人看不见的光。',
        ['捡漏', '鉴宝', '爽文'],
        ['古川', '温雨'],
        80,
        62,
        DramaStatus.ongoing,
        43600000,
        8.3,
      ],
      [
        '哑妻',
        '悬疑',
        '她嫁进这座宅子三年没说过一句话，直到那晚，她开口叫出了凶手的名字。',
        ['悬疑', '宅斗', '反转'],
        ['沈鸢', '裴砚'],
        38,
        38,
        DramaStatus.completed,
        38900000,
        9.1,
      ],
      [
        '修仙从种田开始',
        '玄幻',
        '别人修仙靠灵石，他修仙靠一亩三分地。种着种着，把天道种出来了。',
        ['修仙', '种田', '漫剧'],
        ['陆小七', '阿萝'],
        100,
        87,
        DramaStatus.ongoing,
        35400000,
        8.7,
      ],
      [
        '三个姐姐宠我上天',
        '都市',
        '他有三个姐姐：一个是总裁，一个是影后，一个是顶级律师。而他，只想安静地当个废物。',
        ['团宠', '爽文', '搞笑'],
        ['苏辰', '苏清月'],
        56,
        56,
        DramaStatus.completed,
        31200000,
        8.4,
      ],
      [
        '荒野求生：我的直播间通古代',
        '玄幻',
        '直播荒野求生，弹幕里突然冒出一句"公子，可否借粮"。他抬头，看见了个古装姑娘。',
        ['直播', '穿越', '漫剧'],
        ['林野', '姜禾'],
        64,
        37,
        DramaStatus.ongoing,
        27800000,
        8.5,
      ],
      [
        '睡前故事：一千零一夜',
        '甜宠',
        '他每天给她讲一个故事，讲了一千个夜晚，第一百零一个夜晚她睡着了，他还没说完。',
        ['治愈', '慢热', '温情'],
        ['陆声', '安然'],
        30,
        30,
        DramaStatus.completed,
        19400000,
        9.0,
      ],
    ];

    return List.generate(seeds.length, (i) {
      final s = seeds[i];
      final id = 'demo_${(i + 1).toString().padLeft(3, '0')}';
      return Drama(
        id: id,
        title: s[0] as String,
        category: s[1] as String,
        description: s[2] as String,
        tags: s[3] as List<String>,
        actors: s[4] as List<String>,
        totalEpisodes: s[5] as int,
        updatedEpisodes: s[6] as int,
        status: s[7] as DramaStatus,
        playCount: s[8] as int,
        score: (s[9] as double?) ?? 8.5,
        cover: 'https://picsum.photos/seed/hongguo$id/360/480',
        source: 'demo',
      );
    });
  }
}
