#!/usr/bin/env python3
"""
TravelView Markdown 兼容性检查 —— 保证所有 MD 都能被 pandoc/xelatex 转成 PDF。

用法:
    python3 tools/md-lint.py              # 检查全项目
    python3 tools/md-lint.py a.md b.md    # 检查指定文件
退出码非 0 表示发现问题，可直接挂到 pre-commit 或 CI。

检查项:
  1. emoji 与变体选择符  —— xelatex 无法渲染彩色位图字体，必然报 Missing character
  2. 未被 header.tex 覆盖的生僻符号 —— 会掉字
  3. 未闭合的代码围栏     —— pandoc 会把后半篇文档整个当代码块
"""
import sys, glob, unicodedata

# header.tex 里通过 xeCJKDeclareCharClass 明确交给中文字体的区段
COVERED = [(0x2010,0x2027),(0x2190,0x21FF),(0x2460,0x24FF),
           (0x2500,0x257F),(0x25A0,0x25FF),(0x2600,0x27BF)]
# CJK、全角标点、基本拉丁
SAFE = [(0x0020,0x007E),(0x00A0,0x00FF),(0x2000,0x200F),
        (0x3000,0x303F),(0x3040,0x9FFF),(0xFF00,0xFFEF)]

EMOJI = [(0x1F000,0x1FAFF),(0xFE00,0xFE0F),(0x1F1E6,0x1F1FF),(0x2B00,0x2BFF)]


def cls(o):
    for a, b in EMOJI:
        if a <= o <= b: return "emoji"
    for a, b in COVERED + SAFE:
        if a <= o <= b: return None
    return "uncovered"


def dwidth(s):
    """PDF 里的实际显示宽度。
    汉字/全角 = 2 列。注意「歧义宽度」字符（-> . () 带圈数字等，
    east_asian_width == 'A'）在中文字体里也占 2 列，这是流程图对不齐的头号原因；
    制表符 U+2500-257F 是例外，等宽 CJK 字体里仍是 1 列。"""
    w = 0
    for c in s:
        o = ord(c)
        ea = unicodedata.east_asian_width(c)
        if 0x2500 <= o <= 0x257F:
            w += 1
        elif ea in "WFA":
            w += 2
        else:
            w += 1
    return w


def warn_diagram(path, text):
    """检查带方框的 ASCII 流程图各行显示宽度是否一致 —— 不一致在 PDF 里就是框线错位。
    只看真正的方框行（首尾都是制表符的行），树状目录列表和箭头注释行不参与。"""
    BOX_L, BOX_R = "\u250c\u2514\u251c\u2502", "\u2510\u2518\u2524\u2502"
    inside, block, start = False, [], 0
    for i, line in enumerate(text.splitlines(), 1):
        if line.lstrip().startswith("```"):
            if inside:
                rows = [l.rstrip() for l in block
                        if l.strip() and l.strip()[0] in BOX_L and l.rstrip()[-1] in BOX_R]
                widths = {dwidth(l) for l in rows}
                if len(rows) > 2 and len(widths) > 1:
                    print(f"{path}: [warn] 第 {start} 行起的流程图各行宽度不一致 "
                          f"{sorted(widths)} -> PDF 里框线会错位")
            inside, block, start = not inside, [], i
        elif inside:
            block.append(line)


def check(path):
    text = open(path, encoding="utf-8").read()
    bad = {}
    for i, line in enumerate(text.splitlines(), 1):
        for ch in line:
            k = cls(ord(ch))
            if k:
                bad.setdefault((ch, k), []).append(i)
    if text.count("\n```") % 2:
        bad[("```", "unclosed-fence")] = ["代码围栏数量为奇数"]

    warn_diagram(path, text)

    for (ch, kind), lines in bad.items():
        name = unicodedata.name(ch, "?") if len(ch) == 1 else ""
        where = ", ".join(str(x) for x in lines[:6]) + (" ..." if len(lines) > 6 else "")
        print(f"{path}: [{kind}] {ch!r} U+{ord(ch):04X} {name} -> 行 {where}")
    return len(bad)


def main():
    files = sys.argv[1:] or sorted(glob.glob("**/*.md", recursive=True))
    n = sum(check(f) for f in files)
    if n:
        print(f"\n发现 {n} 类不兼容字符。emoji 请换成纯文本标记（如 **注意**）；")
        print("确需保留的符号，把它的码位加进 tools/pandoc/header.tex 的 xeCJKDeclareCharClass。")
        sys.exit(1)
    print(f"{len(files)} 个 MD 文件均通过 pandoc 兼容性检查")


if __name__ == "__main__":
    main()
