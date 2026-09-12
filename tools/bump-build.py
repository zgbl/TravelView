#!/usr/bin/env python3
"""把版本号 +1，并同步到两个 app 的 pubspec。

    python3 tools/bump-build.py              0.6.0 -> 0.6.1（build 也 +1）
    python3 tools/bump-build.py --set 0.7.0  换一个 base（build 照样 +1）
    python3 tools/bump-build.py --sync       只把 VERSION 写进 pubspec，不动号

**唯一真相是根目录的 VERSION 文件**，pubspec 里的那行是它的副本。
手工改 pubspec 会在下一次 bump 时被覆盖 —— 这是故意的：
两个地方各写各的版本号，迟早会对不上，而对不上的那天你正在查一个
线上 bug，手里那个号是错的。

写进 pubspec 的形式是 `version: 0.6.1+7`:
  0.6.1  给人看的（Flutter 的 versionName / CFBundleShortVersionString）
  7      给商店看的（versionCode / CFBundleVersion），只增不减
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VERSION_FILE = ROOT / 'VERSION'
PUBSPECS = [
    ROOT / 'apps' / 'tv_app' / 'pubspec.yaml',
    ROOT / 'apps' / 'tv_desktop' / 'pubspec.yaml',
]


def read():
    text = VERSION_FILE.read_text(encoding='utf-8')
    out = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        k, _, v = line.partition('=')
        out[k.strip()] = v.strip()
    return text, out['version'], int(out['build'])


def write(text, version, build):
    text = re.sub(r'^version=.*$', f'version={version}', text, flags=re.M)
    text = re.sub(r'^build=.*$', f'build={build}', text, flags=re.M)
    VERSION_FILE.write_text(text, encoding='utf-8')


def sync(version, build):
    for p in PUBSPECS:
        s = p.read_text(encoding='utf-8')
        s, n = re.subn(r'^version:\s*\S+\s*$',
                       f'version: {version}+{build}', s, count=1, flags=re.M)
        if n != 1:
            sys.exit(f'{p} 里没找到 version: 那一行，没敢乱写')
        # Windows 的 MSIX 要四段、而且最后一段必须是 0，
        # 和 pubspec 那行不是同一个格式，得单独写一次
        s = re.sub(r'^(\s*msix_version:\s*)\S+\s*$',
                   rf'\g<1>{version}.0', s, count=1, flags=re.M)
        p.write_text(s, encoding='utf-8')
        print(f'  {p.relative_to(ROOT)}  ->  {version}+{build}')


def main():
    args = sys.argv[1:]
    text, version, build = read()

    if '--sync' in args:
        print(f'同步 {version}+{build}（没有 bump）')
        sync(version, build)
        return

    if '--set' in args:
        version = args[args.index('--set') + 1]
        if not re.fullmatch(r'\d+\.\d+\.\d+', version):
            sys.exit('--set 要三段数字，例如 0.7.0')
    else:
        major, minor, patch = version.split('.')
        version = f'{major}.{minor}.{int(patch) + 1}'

    build += 1
    write(text, version, build)
    print(f'{version}  (build {build})')
    sync(version, build)


if __name__ == '__main__':
    main()
