#!/usr/bin/env bash
# 把 Markdown 转成中文 PDF。转换前先做兼容性检查，有问题直接拦下。
#   ./tools/md2pdf.sh Design/architecture.md
#   ./tools/md2pdf.sh Design/*.md
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

command -v pandoc   >/dev/null || { echo "缺 pandoc:  brew install pandoc"; exit 1; }
command -v xelatex  >/dev/null || { echo "缺 xelatex: brew install --cask mactex-no-gui  (或 basictex)"; exit 1; }

python3 "$ROOT/tools/md-lint.py" "$@"

for f in "$@"; do
  out="${f%.md}.pdf"
  pandoc --defaults="$ROOT/tools/pandoc/defaults.yaml" \
         --include-in-header="$ROOT/tools/pandoc/header.tex" "$f" -o "$out"
  echo "-> $out"
done
