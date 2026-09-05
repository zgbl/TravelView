import 'package:test/test.dart';
import 'package:tv_core/tv_core.dart';

void main() {
  final facts = StopFacts(
    index: 7,
    total: 21,
    arrive: DateTime(2025, 9, 4, 13, 40),
    leave: DateTime(2025, 9, 4, 14, 42),
    photoCount: 54,
    lat: 41.882,
    lon: -87.635,
    placeNames: const ['United States', 'Illinois', 'Chicago', 'Loop'],
    landmarks: const ['Marina City', 'Chicago Riverwalk'],
    arrivedFrom: 'Millennium Park',
    legMeters: 1900,
  );

  group('提示词', () {
    test('包含全部已知事实', () {
      final p = PromptBuilder.forStop(facts);
      expect(p, contains('第 8 站，共 21 站'));
      expect(p, contains('2025-09-04 13:40'));
      expect(p, contains('1 小时 2 分钟'));
      expect(p, contains('54 张'));
      expect(p, contains('Chicago'));
      expect(p, contains('Marina City'));
      expect(p, contains('Millennium Park'));
      expect(p, contains('约 2 公里'));
    });

    test('明确禁止编造 —— 这是文案功能的底线', () {
      final p = PromptBuilder.forStop(facts);
      expect(p, contains('不要编造'));
      expect(p, contains('没写吃了什么就不要写吃的'));
    });

    test('地标要标明"只是附近有"，不能说成去过', () {
      final p = PromptBuilder.forStop(facts);
      expect(p, contains('不代表我去过'));
    });

    test('没有地名时退回坐标，并说明没查到', () {
      final bare = StopFacts(
        index: 0, total: 1,
        arrive: DateTime(2025, 9, 4, 9),
        leave: DateTime(2025, 9, 4, 9, 30),
        photoCount: 3, lat: 36.9147, lon: -111.4558,
      );
      final p = PromptBuilder.forStop(bare);
      expect(p, contains('36.9147'));
      expect(p, contains('没有查到地名'));
    });

    test('用户补充的信息会被带上', () {
      final p = PromptBuilder.forStop(facts, userHint: '坐了游船，风很大');
      expect(p, contains('我补充的信息'));
      expect(p, contains('坐了游船'));
    });

    test('语言、语气、字数可控', () {
      final p = PromptBuilder.forStop(facts,
          language: 'English', tone: '生动一些', maxWords: 40);
      expect(p, contains('用English写'));
      expect(p, contains('语气生动一些'));
      expect(p, contains('不超过 40 字'));
    });
  });

  group('解析 AI 返回', () {
    test('拆出标题和正文', () {
      final d = AiDraft.parse('标题: 河上的一小时\n'
          '从千禧公园走到河边，坐船看了一圈老桥。');
      expect(d.title, '河上的一小时');
      expect(d.note, contains('老桥'));
      expect(d.note, isNot(contains('标题')));
    });

    test('英文 title: 也认', () {
      final d = AiDraft.parse('Title: An hour on the river\nWe took a boat.');
      expect(d.title, 'An hour on the river');
      expect(d.note, 'We took a boat.');
    });

    test('没有标题时正文完整保留', () {
      final d = AiDraft.parse('就是很普通的一段话。\n第二行。');
      expect(d.title, '');
      expect(d.note, '就是很普通的一段话。\n第二行。');
    });

    test('空输入不崩', () {
      final d = AiDraft.parse('');
      expect(d.title, '');
      expect(d.note, '');
    });
  });

  group('站点文字的键', () {
    test('用最早那张照片的 id，重新聚类后依然对得上', () {
      final stop = Stop(
        seq: 3, lat: 41.88, lon: -87.63,
        arrive: DateTime(2025, 9, 4, 13),
        leave: DateTime(2025, 9, 4, 14),
        photoIds: const ['photoA', 'photoB'],
      );
      final renumbered = Stop(
        seq: 9, lat: 41.79, lon: -87.51, // 换了聚类半径，seq 和中心都变了
        arrive: DateTime(2025, 9, 4, 13),
        leave: DateTime(2025, 9, 4, 15),
        photoIds: const ['photoA', 'photoB', 'photoC'],
      );
      expect(NoteStore.keyFor(stop), NoteStore.keyFor(renumbered),
          reason: '调聚类参数不该让写好的文字全部对不上');
    });
  });
}
