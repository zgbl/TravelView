import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tv_core/tv_core.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('tv_pub');
    await Directory(p.join(tmp.path, 'photos')).create(recursive: true);
    await File(p.join(tmp.path, 'story.json')).writeAsString('{"version":1}');
  });

  tearDown(() => tmp.delete(recursive: true));

  const cfg = PublishConfig(siteUrl: 'https://x.test/', token: 'tv_1');

  test('接口地址拼接不重复斜杠', () {
    expect(cfg.publishUri.toString(), 'https://x.test/api/publish');
  });

  test('没有令牌就不发请求', () async {
    const bad = PublishConfig(siteUrl: 'https://x.test', token: '');
    expect(bad.isConfigured, isFalse);
    await expectLater(
      const Publisher(bad).publish(tmp),
      throwsA(isA<PublishException>()),
    );
  });

  test('缺少 story.json 直接报错，不去连服务器', () async {
    await File(p.join(tmp.path, 'story.json')).delete();
    await expectLater(
      const Publisher(cfg).publish(tmp),
      throwsA(isA<PublishException>()
          .having((e) => e.message, 'message', contains('story.json'))),
    );
  });

  test('目录里出现原图，本地就拦住，绝不上传', () async {
    await File(p.join(tmp.path, 'photos', 'a.webp')).writeAsBytes([1]);
    await File(p.join(tmp.path, 'photos', 'IMG_0001.HEIC'))
        .writeAsBytes([1]);
    await expectLater(
      const Publisher(cfg).publish(tmp),
      throwsA(isA<PublishException>()
          .having((e) => e.message, 'message', contains('拒绝上传'))),
    );
  });

  test('没有图片时不创建 Story', () async {
    await expectLater(
      const Publisher(cfg).publish(tmp),
      throwsA(isA<PublishException>()
          .having((e) => e.message, 'message', contains('没有可上传'))),
    );
  });

  test('402 认成需要付款', () {
    const e = PublishException('额度不够', statusCode: 402);
    expect(e.needsPayment, isTrue);
    expect(const PublishException('x', statusCode: 500).needsPayment, isFalse);
  });
}
