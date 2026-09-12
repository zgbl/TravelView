import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_shared/tv_shared.dart';

void main() {
  test('英文名直接推出地址', () {
    expect(HandleRules.suggest(name: 'Xinyu Tu'), 'xinyu_tu');
    expect(HandleRules.suggest(name: '  Mary-Jane  '), 'mary_jane');
  });

  test('中文名推不出来时退回邮箱前缀', () {
    expect(HandleRules.suggest(name: '李小明', email: 'zgbl123@yahoo.com'),
        'zgbl123');
  });

  test('推出来的永远是合法的', () {
    for (final n in ['A', 'ab', '...', '张三', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'Hi there']) {
      final h = HandleRules.suggest(name: n, email: 'x@y.com');
      expect(HandleRules.isValid(h), isTrue, reason: '来自 "$n" 的 "$h"');
    }
  });

  test('换一个：保住原来的名字，只挂后缀', () {
    final v = HandleRules.vary('xinyu_tu', random: Random(3));
    expect(v.startsWith('xinyu_tu_'), isTrue);
    expect(HandleRules.isValid(v), isTrue);
  });

  test('换一个：超长的也要合法', () {
    for (var seed = 0; seed < 20; seed++) {
      final v = HandleRules.vary('aaaaaaaaaaaaaaaaaaaa', random: Random(seed));
      expect(HandleRules.isValid(v), isTrue, reason: 'seed $seed -> "$v"');
    }
  });
}
