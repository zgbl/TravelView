#!/usr/bin/env python3
"""Dart 括号平衡粗查。我这边装不了 Dart，用它拦掉最低级的语法错。

注意剥离顺序: 必须先剥字符串再剥注释 —— 否则 URL 里的 // 会被误当成注释，
把后面的括号一起吃掉，产生假警报。
"""
import re, sys, glob

def check(path):
    s = open(path, encoding='utf-8').read()
    t = re.sub(r"r?'''.*?'''", 'S', s, flags=re.S)
    t = re.sub(r'r?""".*?"""', 'S', t, flags=re.S)
    t = re.sub(r"r?'(\\.|[^'\\\n])*'", 'S', t)
    t = re.sub(r'r?"(\\.|[^"\\\n])*"', 'S', t)
    t = re.sub(r'//[^\n]*', '', t)
    pairs = {'{}': ('{', '}'), '()': ('(', ')'), '[]': ('[', ']')}
    return {k: t.count(a) - t.count(b) for k, (a, b) in pairs.items()}

def main():
    files = sys.argv[1:] or sorted(glob.glob('**/*.dart', recursive=True))
    bad = 0
    for f in files:
        r = check(f)
        if any(r.values()):
            print(f'BAD  {f}  {r}')
            bad += 1
    print(f'{len(files)} 个文件检查完毕，{bad} 个可疑')
    sys.exit(1 if bad else 0)

if __name__ == '__main__':
    main()
