#!/usr/bin/env bash
# dev-sync.sh — 开发模式同步：将 ~/.meta-skill/ 中的源码替换为指向 GitHub 仓库的符号链接
#
# 效果：
#   - 编辑 ~/.meta-skill/scripts/lib.sh = 编辑 GitHub 仓库的 scripts/lib.sh（实时同步）
#   - 运行时数据（manifest.json, registry.json, skills/ECC 等）保持独立，不污染 GitHub
#   - GitHub 项目的 .gitignore 已排除运行时文件
#
# Usage:
#   ./scripts/dev-sync.sh          # 切换到开发模式（源码 → 符号链接）
#   ./scripts/dev-sync.sh --revert # 恢复为独立拷贝（从 GitHub 复制回 ~/.meta-skill/）

set -euo pipefail

# 动态获取脚本所在目录的上级目录（项目根目录）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(dirname "$SCRIPT_DIR")"
META_HOME="${HOME}/.meta-skill"

# 需要链接的源码文件/目录（相对路径，相对于 SOURCE_DIR）
# 格式：源码相对路径|运行时目标路径（相对于 META_HOME）
LINK_MAP=(
  "scripts|scripts"
  "install.sh|install.sh"
  "SKILL.md|skills/meta-skill/SKILL.md"
  "skills|skills/meta-skill/skills"
  "meta-skill.sh|bin/meta-skill"
)

info()  { echo "[dev-sync] $*"; }
warn()  { echo "[dev-sync] WARN: $*" >&2; }
die()   { echo "[dev-sync] ERROR: $*" >&2; exit 1; }

# 检查 GitHub 源码目录
[[ -d "$SOURCE_DIR/.git" ]] || die "Source dir is not a git repo: $SOURCE_DIR"

# 确保目标目录存在
mkdir -p "$META_HOME/bin"
mkdir -p "$META_HOME/skills/meta-skill"

revert=false
[[ "${1:-}" == "--revert" ]] && revert=true

if $revert; then
  info "Reverting to standalone copies (dev mode → normal mode)..."
else
  info "Switching to dev mode (symlinks → $SOURCE_DIR)..."
fi

for entry in "${LINK_MAP[@]}"; do
  src_rel="${entry%%|*}"
  dst_rel="${entry##*|}"
  src_path="$SOURCE_DIR/$src_rel"
  dst_path="$META_HOME/$dst_rel"

  if [[ ! -e "$src_path" ]]; then
    warn "Source not found: $src_path, skipping"
    continue
  fi

  # 如果已经是符号链接，先删除
  if [[ -L "$dst_path" ]]; then
    rm "$dst_path"
    info "  Removed existing symlink: $dst_rel"
  elif [[ -e "$dst_path" ]]; then
    # 是真实文件/目录，备份后删除
    backup="${dst_path}.bak.$(date +%s)"
    mv "$dst_path" "$backup"
    info "  Backed up existing: $dst_rel → $(basename "$backup")"
  fi

  if $revert; then
    # 恢复模式：从 GitHub 复制
    if [[ -d "$src_path" ]]; then
      cp -R "$src_path" "$dst_path"
    else
      cp "$src_path" "$dst_path"
    fi
    chmod +x "$dst_path" 2>/dev/null || true
    info "  Copied: $src_rel → $dst_rel"
  else
    # 开发模式：创建符号链接
    ln -s "$src_path" "$dst_path"
    info "  Linked: $dst_rel → $src_rel"
  fi
done

if $revert; then
  info "Done! ~/.meta-skill/ now uses standalone copies."
else
  info "Done! ~/.meta-skill/ source files now symlink to $SOURCE_DIR"
  info "Edits to either location are instantly synchronized."
  info "Run with --revert to switch back to standalone copies."
fi
