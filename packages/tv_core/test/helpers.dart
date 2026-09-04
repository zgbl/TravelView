import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

Directory makeTempLib() =>
    Directory.systemTemp.createTempSync('tv_lib_');

/// 造一个内容确定的假"照片"文件（内容由 seed 决定，方便断言去重）
File makeFakePhoto(Directory dir, String name, {int seed = 1, int size = 4096}) {
  final rnd = Random(seed);
  final bytes = List<int>.generate(size, (_) => rnd.nextInt(256));
  final f = File(p.join(dir.path, name));
  f.parent.createSync(recursive: true);
  f.writeAsBytesSync(bytes);
  return f;
}

DateTime at(int y, int mo, int d, [int h = 12, int mi = 0, int s = 0]) =>
    DateTime(y, mo, d, h, mi, s);
