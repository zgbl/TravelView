import 'package:test/test.dart';
import 'package:tv_core/tv_core.dart';

import 'helpers.dart';

void main() {
  test('相同内容不同文件名 -> 相同 id', () async {
    final dir = makeTempLib();
    final a = makeFakePhoto(dir, 'a.jpg', seed: 7);
    final b = makeFakePhoto(dir, 'b.jpg', seed: 7);
    expect(await Fingerprint.contentId(a), await Fingerprint.contentId(b));
    dir.deleteSync(recursive: true);
  });

  test('不同内容 -> 不同 id', () async {
    final dir = makeTempLib();
    final a = makeFakePhoto(dir, 'a.jpg', seed: 1);
    final b = makeFakePhoto(dir, 'b.jpg', seed: 2);
    expect(await Fingerprint.contentId(a),
        isNot(await Fingerprint.contentId(b)));
    dir.deleteSync(recursive: true);
  });

  test('快速指纹能筛掉不同大小的文件', () async {
    final dir = makeTempLib();
    final a = makeFakePhoto(dir, 'a.jpg', seed: 1, size: 1000);
    final b = makeFakePhoto(dir, 'b.jpg', seed: 1, size: 2000);
    expect(await Fingerprint.quickFingerprint(a),
        isNot(await Fingerprint.quickFingerprint(b)));
    dir.deleteSync(recursive: true);
  });

  test('空文件不崩', () async {
    final dir = makeTempLib();
    final f = makeFakePhoto(dir, 'empty.jpg', size: 0);
    expect(await Fingerprint.quickFingerprint(f), startsWith('0-'));
    dir.deleteSync(recursive: true);
  });
}
