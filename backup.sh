#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# TravelView 项目备份脚本
# 遵循惯例：全量纯净源码/配置快照，排除构建产物、依赖库、本地缓存与敏感信息
#
# 完整路径说明:
#   - 项目源码目录: /Users/tuxy/Codes/Github3/TravelView
#   - 默认备份根目录: /Users/tuxy/Codes/Github3/TravelView/release
#   - 独立备份根目录(可选): /Users/tuxy/Codes/Backup/TravelView/release
#
# 使用方法:
#   /Users/tuxy/Codes/Github3/TravelView/backup.sh
#       -> 备份到 /Users/tuxy/Codes/Github3/TravelView/release/TravelView-YYYYMMDD_HHMMSS
#   /Users/tuxy/Codes/Github3/TravelView/backup.sh /Users/tuxy/Codes/Backup/TravelView/release
#       -> 备份到 /Users/tuxy/Codes/Backup/TravelView/release/TravelView-YYYYMMDD_HHMMSS
# ─────────────────────────────────────────────────────────────────────────────

# 终端彩色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# 项目绝对根路径
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP="$(date +"%Y%m%d_%H%M%S")"

# 默认备份目标根目录完整路径: /Users/tuxy/Codes/Github3/TravelView/release
DEFAULT_BACKUP_ROOT="${PROJECT_ROOT}/release"
BACKUP_ROOT="${1:-${BACKUP_ROOT:-$DEFAULT_BACKUP_ROOT}}"
TARGET_DIR="${BACKUP_ROOT}/TravelView-${TIMESTAMP}"

echo -e "${GREEN}🚀 开始 TravelView 项目备份...${NC}"
echo -e "${YELLOW}📁 项目源路径: ${PROJECT_ROOT}${NC}"
echo -e "${YELLOW}📁 备份目标绝对路径: ${TARGET_DIR}${NC}"

# 创建目标目录
mkdir -p "$TARGET_DIR"


cd "$PROJECT_ROOT"

# 执行 rsync 备份并排除无关的大型临时文件与产物
rsync -a --delete \
  --exclude ".git/" \
  --exclude ".DS_Store" \
  --exclude "*.log" \
  --exclude "*.tmp" \
  --exclude "node_modules/" \
  --exclude ".next/" \
  --exclude "dist/" \
  --exclude "build/" \
  --exclude ".dart_tool/" \
  --exclude ".flutter-plugins" \
  --exclude ".flutter-plugins-dependencies" \
  --exclude ".packages" \
  --exclude ".fvm/" \
  --exclude "*.iml" \
  --exclude "Pods/" \
  --exclude ".symlinks/" \
  --exclude "DerivedData/" \
  --exclude "xcuserdata/" \
  --exclude "**/Flutter/ephemeral/" \
  --exclude "**/flutter/ephemeral/" \
  --exclude "**/android/.gradle/" \
  --exclude "**/android/local.properties" \
  --exclude "release/" \
  --exclude "releases/" \
  --exclude "test-output/runs/" \
  --exclude "_to_delete/" \
  --exclude "__pycache__/" \
  --exclude ".pytest_cache/" \
  --exclude "*.pyc" \
  --exclude ".env" \
  --exclude ".env.*" \
  --exclude "*.local" \
  --exclude "*.jks" \
  --exclude "*.keystore" \
  ./ "$TARGET_DIR/"

# 确保备份目录保留一份 backup.sh
cp "$PROJECT_ROOT/backup.sh" "$TARGET_DIR/backup.sh"

# 生成备份信息元数据
GIT_BRANCH=$(git branch --show-current 2>/dev/null || echo "未知")
GIT_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "未知")
GIT_DIRTY=$(git status -s 2>/dev/null | wc -l | tr -d ' ')

cat > "$TARGET_DIR/backup_info.txt" << EOF
================================================================================
 TravelView 备份元数据 (Backup Metadata)
================================================================================
备份时间: $(date)
项目名称: TravelView
源路径:   $PROJECT_ROOT
目标路径: $TARGET_DIR

Git 信息:
  - 当前分支: $GIT_BRANCH
  - 提交版本: $GIT_COMMIT
  - 未提交变动项数: $GIT_DIRTY

包含模块:
  - apps/ (Flutter 移动与桌面客户端纯源码)
  - web/ (Next.js Web 源码与配置，排除 node_modules/.next)
  - shared/ (共享核心逻辑与静态品牌素材)
  - packages/ (本地依赖包)
  - tools/ (构建及辅助工具脚本)
  - docs/ & Design/ (设计文档与架构规范)
  - CF-Assignment/ (Cloudflare Assignment 需求文档)
  - 核心配置 (VERSION, README.md, package.json 等)

排除项目:
  - 依赖项 (node_modules, Pods 等)
  - 编译构建缓存 (.dart_tool, build/, dist/, .next/ 等)
  - 临时测试产物 (test-output/runs/ 等)
  - 系统与敏感文件 (.git, .env, *.keystore, .DS_Store 等)
================================================================================
EOF

BACKUP_SIZE=$(du -sh "$TARGET_DIR" | cut -f1)

echo ""
echo -e "${GREEN}✅ 备份完成！${NC}"
echo -e "${CYAN}📊 备份大小: ${BOLD}$BACKUP_SIZE${NC}"
echo -e "${CYAN}📁 备份路径: $TARGET_DIR${NC}"
echo -e "${CYAN}📝 备份信息已写入: $TARGET_DIR/backup_info.txt${NC}"

# 列出最近历史备份
if [ -d "$BACKUP_ROOT" ]; then
    echo -e "\n${YELLOW}🕒 最近备份列表 (前5项):${NC}"
    ls -ltd "$BACKUP_ROOT"/TravelView-* 2>/dev/null | head -5 || true
fi
