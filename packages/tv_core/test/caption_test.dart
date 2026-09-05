import 'package:test/test.dart';
import 'package:tv_core/tv_core.dart';

StopFacts facts({
  DateTime? arrive,
  Duration stay = const Duration(hours: 2),
  int photos = 12,
  List<String> places = const ['美国', '亚利桑那州', '页岩城'],
  List<String> landmarks = const [],
  String? from,
  double? meters,
  String? mode,
}) {
  final a = arrive ?? DateTime(2025, 9, 14, 15, 30);
  return StopFacts(
    index: 2,
    total: 9,
    arrive: a,
    leave: a.add(stay),
    photoCount: photos,
    lat: 36.9,
    lon: -111.4,
    placeNames: places,
    landmarks: landmarks,
    arrivedFrom: from,
    legMeters: meters,
    legMode: mode,
  );
}

void main() {
  test('标题取最具体的地名', () {
    expect(FactCaption.forStop(facts()).title, '页岩城');
  });

  test('没有地名时退回站序，不留空', () {
    final c = FactCaption.forStop(facts(places: []));
    expect(c.title, '第 3 站');
    expect(c.text, contains('到达'));
  });

  test('正文包含时间、地点和照片数', () {
    final t = FactCaption.forStop(facts()).text;
    expect(t, contains('9 月 14 日下午'));
    expect(t, contains('亚利桑那州页岩城'));
    expect(t, contains('12 张照片'));
    expect(t, contains('停留约 2 小时'));
  });

  test('几分钟的路过不写停留时长', () {
    final t = FactCaption.forStop(facts(stay: const Duration(minutes: 6))).text;
    expect(t, isNot(contains('停留')));
  });

  test('地标措辞是"这一带有"，绝不说去过', () {
    final t = FactCaption.forStop(
        facts(landmarks: ['马蹄湾', '羚羊峡谷', '鲍威尔湖', '格伦峡谷大坝'])).text;
    expect(t, contains('这一带有'));
    expect(t, isNot(contains('参观')));
    expect(t, isNot(contains('游览')));
    // 只列前三个
    expect(t, isNot(contains('格伦峡谷大坝')));
  });

  test('上一站和里程写进来', () {
    final t = FactCaption.forStop(
        facts(from: '拉斯维加斯', meters: 431000, mode: 'drive')).text;
    expect(t, contains('从拉斯维加斯开过来'));
    expect(t, contains('431 公里'));
  });

  test('不编造任何未给出的事实', () {
    final t = FactCaption.forStop(facts()).text;
    for (final banned in ['天气', '我们吃', '同伴', '仿佛', '令人']) {
      expect(t, isNot(contains(banned)));
    }
  });

  test('下级地名里已经含着上级时不重复拼', () {
    final t = FactCaption.forStop(facts(places: ['美国', '美国俄亥俄州'])).text;
    expect(t, contains('美国俄亥俄州'));
    expect(t, isNot(contains('美国美国')));
  });

  test('张数说的是"共拍了"，和页面上的精选张数不会打架', () {
    expect(FactCaption.forStop(facts()).text, contains('共拍了 12 张'));
  });
}
