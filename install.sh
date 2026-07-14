#!/usr/bin/env bash
# meta-skill installer (macOS / Linux)
# Usage: curl -fsSL https://raw.githubusercontent.com/user/meta-skill/main/install.sh | bash
#    or: ./install.sh [--github <url>]

set -euo pipefail

META_HOME="${HOME}/.meta-skill"
SKILLS_DIR="${META_HOME}/skills"
MANIFESTS_DIR="${META_HOME}/manifests"
BIN_DIR="${META_HOME}/bin"
TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/templates"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse args
GITHUB_URL="${GITHUB_URL:-https://github.com/user/meta-skill}"
INSTALL_ALL=false
INSTALL_IDES=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --github)  GITHUB_URL="$2"; shift 2 ;;
    --version) META_VERSION="$2"; shift 2 ;;
    --all)     INSTALL_ALL=true; shift ;;
    --ide)     INSTALL_IDES="$2"; shift 2 ;;
    *) shift ;;
  esac
done

META_VERSION="${META_VERSION:-1.0.0}"

info() { echo "[meta-skill installer] $*"; }
warn() { echo "[meta-skill installer] WARN: $*" >&2; }

# ---- preflight ----

info "=== meta-skill installer v${META_VERSION} ==="
info "Install destination: ${META_HOME}"

# ---- detect environment ----
detect_pkg_manager() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    if command -v brew &> /dev/null; then
      echo "brew"
    else
      echo "macos-no-brew"
    fi
  elif [[ "$(uname -s)" == "Linux" ]]; then
    if command -v apt &> /dev/null; then
      echo "apt"
    elif command -v dnf &> /dev/null; then
      echo "dnf"
    elif command -v yum &> /dev/null; then
      echo "yum"
    elif command -v pacman &> /dev/null; then
      echo "pacman"
    elif command -v apk &> /dev/null; then
      echo "apk"
    else
      echo "linux-unknown"
    fi
  else
    echo "unknown"
  fi
}

PKG_MGR=$(detect_pkg_manager)

# ---- preflight: check dependencies ----

MISSING_CMDS=()

for cmd in git jq bash; do
  if ! command -v "$cmd" &> /dev/null; then
    MISSING_CMDS+=("$cmd")
  fi
done

if [[ ${#MISSING_CMDS[@]} -gt 0 ]]; then
  echo
  warn "Missing dependencies: ${MISSING_CMDS[*]}"
  echo

  case "$PKG_MGR" in
    brew)
      echo "  Your system: macOS with Homebrew"
      echo "  Run: brew install ${MISSING_CMDS[*]}"
      ;;
    macos-no-brew)
      echo "  Your system: macOS (Homebrew not found)"
      echo "  Install Homebrew first: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
      echo "  Then run: brew install ${MISSING_CMDS[*]}"
      ;;
    apt)
      echo "  Your system: Linux (apt)"
      echo "  Run: sudo apt update && sudo apt install ${MISSING_CMDS[*]}"
      ;;
    dnf)
      echo "  Your system: Linux (dnf)"
      echo "  Run: sudo dnf install ${MISSING_CMDS[*]}"
      ;;
    yum)
      echo "  Your system: Linux (yum)"
      echo "  Run: sudo yum install ${MISSING_CMDS[*]}"
      ;;
    pacman)
      echo "  Your system: Linux (pacman)"
      echo "  Run: sudo pacman -S ${MISSING_CMDS[*]}"
      ;;
    apk)
      echo "  Your system: Linux (apk)"
      echo "  Run: sudo apk add ${MISSING_CMDS[*]}"
      ;;
    *)
      echo "  Please install the missing dependencies using your system's package manager,"
      echo "  then re-run this installer."
      ;;
  esac
  echo
  exit 1
fi

info "All dependencies satisfied."

# ---- create directory structure ----

info "Creating directory structure..."

mkdir -p "$SKILLS_DIR"
mkdir -p "$MANIFESTS_DIR"
mkdir -p "$BIN_DIR"
mkdir -p "${META_HOME}/backups"

# ---- install metadata.json ----

if [[ -f "${TEMPLATE_DIR}/metadata.json" ]]; then
  jq --arg version "$META_VERSION" \
     --arg github "$GITHUB_URL" \
     --arg created_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
     --arg updated_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
     '.version = $version | .github = $github | .created_at = $created_at | .updated_at = $updated_at' \
     "${TEMPLATE_DIR}/metadata.json" > "${META_HOME}/metadata.json"
  info "metadata.json created"
else
  # Fallback: generate from script directory
  cat > "${META_HOME}/metadata.json" <<METAEOF
{
  "name": "meta-skill",
  "version": "${META_VERSION}",
  "description": "Universal skill manager for AI coding agents",
  "github": "${GITHUB_URL}",
  "created_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "updated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
METAEOF
  info "metadata.json created (fallback)"
fi

# ---- install registry.json ----

if [[ -f "${TEMPLATE_DIR}/registry.json" ]]; then
  if [[ -f "${META_HOME}/registry.json" ]]; then
    # Merge: keep existing registry, add any new agents/sources from template
    jq -s '.[0] as $current | .[1] as $template |
      $current | .agents += ($template.agents | with_entries(select(.key as $k | $current.agents | has($k) | not))) |
      .sources += ($template.sources | with_entries(select(.key as $k | $current.sources | has($k) | not)))' \
      "${META_HOME}/registry.json" "${TEMPLATE_DIR}/registry.json" > "${META_HOME}/registry.json.tmp"
    mv "${META_HOME}/registry.json.tmp" "${META_HOME}/registry.json"
    info "registry.json updated (merged new agents/sources from template)"
  else
    cp "${TEMPLATE_DIR}/registry.json" "${META_HOME}/registry.json"
    info "registry.json created"
  fi
else
  warn "registry.json template not found, creating minimal registry..."
  if [[ ! -f "${META_HOME}/registry.json" ]]; then
    cat > "${META_HOME}/registry.json" <<REGEOF
{
  "version": "1.0.0",
  "agents": {},
  "sources": {}
}
REGEOF
  fi
fi

# ---- install manifest.json ----

if [[ ! -f "${META_HOME}/manifest.json" ]]; then
  cat > "${META_HOME}/manifest.json" <<MANEOF
{
  "skills": {}
}
MANEOF
  info "manifest.json created"
fi

# ---- migrate old manifest format (single-file → per-skill files) ----

migrate_manifest() {
  local manifest="${META_HOME}/manifest.json"
  if [[ ! -f "$manifest" ]]; then
    return
  fi

  # Detect old format: any skill entry with non-empty value (has 'source' field)
  local needs_migration
  needs_migration=$(jq '.skills | to_entries | any(.value | has("source"))' "$manifest" 2>/dev/null || echo "false")

  if [[ "$needs_migration" != "true" ]]; then
    return
  fi

  info "Migrating manifest to per-skill format..."
  mkdir -p "${MANIFESTS_DIR}"
  mkdir -p "${META_HOME}/backups"

  # Backup old manifest
  cp "$manifest" "${META_HOME}/backups/manifest_pre_migration_$(date -u +%Y%m%dT%H%M%SZ).json"

  # Extract each skill entry to its own file
  local names
  names=$(jq -r '.skills | keys[]' "$manifest")
  local count=0
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    jq ".skills[\"$name\"]" "$manifest" > "${MANIFESTS_DIR}/${name}.json"
    ((count++)) || true
  done <<< "$names"

  # Rewrite manifest as thin index
  jq '.skills = (.skills | map_values({}))' "$manifest" > "${manifest}.tmp"
  mv "${manifest}.tmp" "$manifest"

  info "Migration complete: $count skill(s) moved to per-skill files"
}

migrate_manifest

# ---- install meta-skill CLI ----

cp "${SCRIPT_DIR}/meta-skill.sh" "${BIN_DIR}/meta-skill"
chmod +x "${BIN_DIR}/meta-skill"
info "CLI installed: ${BIN_DIR}/meta-skill"

# ---- install operation scripts ----

SCRIPTS_DEST="${META_HOME}/scripts"
mkdir -p "$SCRIPTS_DEST"
if [[ -d "${SCRIPT_DIR}/scripts" ]]; then
  for s in "${SCRIPT_DIR}/scripts/"*.sh; do
    if [[ -f "$s" ]]; then
      cp "$s" "$SCRIPTS_DEST/"
      chmod +x "${SCRIPTS_DEST}/$(basename "$s")"
    fi
  done
  info "Operation scripts installed: $SCRIPTS_DEST"
fi

# ---- install sub-skill docs into skills/meta-skill/skills/ ----
# 子 skill 文档作为 meta-skill 的内部资源，不作为独立 skill 注册

if [[ -d "${SCRIPT_DIR}/skills" ]]; then
  mkdir -p "${SKILLS_DIR}/meta-skill/skills"
  for skill_dir in "${SCRIPT_DIR}/skills/"*/; do
    skill_md="${skill_dir}SKILL.md"
    if [[ -f "$skill_md" ]]; then
      skill_name=$(basename "$skill_dir")
      mkdir -p "${SKILLS_DIR}/meta-skill/skills/${skill_name}"
      cp "$skill_md" "${SKILLS_DIR}/meta-skill/skills/${skill_name}/SKILL.md"
      info "Sub-skill doc installed: $skill_name"
    fi
  done
fi

# ---- register meta-skill itself in manifest ----

ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Register meta-skill as a managed skill (source = the GitHub repo)
# Determine target agents: --ide flag restricts, otherwise link to all known agents
if [[ -n "$INSTALL_IDES" ]]; then
  target_agents=$(echo "$INSTALL_IDES" | jq -R 'split(",")')
else
  target_agents=$(jq '.agents | keys' "${META_HOME}/registry.json")
fi

# Write meta-skill entry to per-skill file
jq -n \
   --arg ts "$ts" \
   --arg type "github" \
   --arg url "$GITHUB_URL" \
   --arg version "$META_VERSION" \
   --argjson agents "$target_agents" \
   '{
      source: { type: $type, url: $url, version: $version },
      installed_at: $ts,
      updated_at: $ts,
      agents: $agents,
      projects: {}
    }' > "${MANIFESTS_DIR}/meta-skill.json"

# Rebuild manifest.json index from per-skill files
names_json=$(for mfile in "${MANIFESTS_DIR}"/*.json; do
  [[ ! -f "$mfile" ]] && continue
  basename "$mfile" .json
done | jq -R . | jq -s .)

jq -n --argjson names "$names_json" \
  '{skills: ($names | map({key: ., value: {}}) | from_entries)}' \
  > "${META_HOME}/manifest.json"

info "meta-skill registered in manifest"

# ---- create meta-skill SKILL.md if not already present ----

if [[ ! -f "${SKILLS_DIR}/meta-skill/SKILL.md" ]]; then
  mkdir -p "${SKILLS_DIR}/meta-skill"
  cp "${SCRIPT_DIR}/SKILL.md" "${SKILLS_DIR}/meta-skill/SKILL.md"
  info "meta-skill SKILL.md created"
fi

# ---- link meta-skill to AI agents ----

info "Linking meta-skill to AI agents..."

# Determine which agents to link to
# All modes check agent home directory existence to avoid creating empty dirs for uninstalled IDEs
# --all:   all agents whose home directory exists
# --ide:   specified agents whose home directory exists

agent_filter() {
  local key="$1"
  local home_raw="$2"

  # All paths require agent home directory to exist
  local home_dir
  home_dir=$(eval echo "$home_raw")
  if [[ ! -d "$home_dir" ]]; then
    return 1
  fi

  # 检查 home 目录下是否有 skills 以外的内容（区分真正安装的 IDE vs meta-skill 创建的空壳）
  local non_skills_count
  non_skills_count=$(find "$home_dir" -maxdepth 1 -not -name "skills" -not -name ".DS_Store" -not -path "$home_dir" 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$non_skills_count" -eq 0 ]]; then
    return 1
  fi

  # --all: all installed agents (home exists and has content)
  if $INSTALL_ALL; then
    return 0
  fi

  # --ide: only specified agents (and home exists)
  if [[ -n "$INSTALL_IDES" ]]; then
    local IFS=','
    for id in $INSTALL_IDES; do
      [[ "$id" == "$key" ]] && return 0
    done
    return 1
  fi

  # Default: home exists (already checked above)
  return 0
}

agents=$(jq -r '.agents | to_entries[] | "\(.key) \(.value.home) \(.value.skill_dir)"' "${META_HOME}/registry.json")

linked=0 skipped=0
if [[ -n "$agents" ]]; then
  while read -r agent_key home_raw skill_dir; do
    [[ -z "$agent_key" || -z "$skill_dir" ]] && continue

    if ! agent_filter "$agent_key" "$home_raw"; then
      info "  Skipping $agent_key (home directory not found, agent not installed)"
      ((skipped++)) || true
      continue
    fi

    agent_skills_dir=$(eval echo "$skill_dir")  # expand ~
    mkdir -p "$agent_skills_dir"
    link_path="${agent_skills_dir}/meta-skill"
    if [[ ! -e "$link_path" ]]; then
      ln -s "${SKILLS_DIR}/meta-skill" "$link_path"
      info "  Linked to $agent_key ($agent_skills_dir)"
      ((linked++)) || true
    else
      info "  Already linked: $agent_key"
      ((linked++)) || true
    fi
  done <<< "$agents"
fi

info "Linked: $linked, Skipped: $skipped"

# ---- PATH configuration ----

need_path=false
shell_rc=""

case "${SHELL:-}" in
  */zsh)  shell_rc="${HOME}/.zshrc" ;;
  */bash) shell_rc="${HOME}/.bashrc" ;;
  *)      shell_rc="${HOME}/.profile" ;;
esac

if ! echo "$PATH" | tr ':' '\n' | grep -q "${BIN_DIR}"; then
  need_path=true
fi

if $need_path; then
  if [[ -f "$shell_rc" ]]; then
    if ! grep -q "${BIN_DIR}" "$shell_rc"; then
      echo "" >> "$shell_rc"
      echo "# meta-skill" >> "$shell_rc"
      echo "export PATH=\"${BIN_DIR}:\$PATH\"" >> "$shell_rc"
      info "Added ${BIN_DIR} to PATH in ${shell_rc}"
    else
      info "${BIN_DIR} already in ${shell_rc}"
    fi
  else
    echo "# meta-skill" > "$shell_rc"
    echo "export PATH=\"${BIN_DIR}:\$PATH\"" >> "$shell_rc"
    info "Created ${shell_rc} with PATH entry"
  fi
else
  info "${BIN_DIR} already in PATH"
fi

# ---- summary ----

echo
info "========================================="
info " meta-skill installed successfully!"
info "========================================="
echo
echo "  Location: ${META_HOME}"
echo "  CLI:      ${BIN_DIR}/meta-skill"
echo
echo "  Quick start:"
echo "    meta-skill list"
echo "    meta-skill install <name> --source <url> --agent trae"
echo
if $need_path; then
  echo "  Restart your shell or run: source ${shell_rc}"
  echo
fi
