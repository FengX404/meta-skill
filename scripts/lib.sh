#!/usr/bin/env bash
# meta-skill shared library
# Sourced by individual operation scripts and the dispatcher.

set -euo pipefail

META_HOME="${HOME}/.meta-skill"
MANIFEST="${META_HOME}/manifest.json"
MANIFESTS_DIR="${META_HOME}/manifests"
REGISTRY="${META_HOME}/registry.json"
SKILLS_DIR="${META_HOME}/skills"
METADATA="${META_HOME}/metadata.json"

# ---- logging ----

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "[meta-skill] $*"; }
warn() { echo "[meta-skill] WARN: $*" >&2; }

# ---- manifest ----

read_manifest() {
  if [[ ! -f "$MANIFEST" ]]; then
    die "manifest.json not found at $MANIFEST. Run meta-skill installer first."
  fi
  cat "$MANIFEST"
}

write_manifest() {
  local tmp="${MANIFEST}.tmp.$$"
  cat > "$tmp"
  if [[ -f "$MANIFEST" ]]; then
    local backup_dir="${META_HOME}/backups"
    mkdir -p "$backup_dir"
    cp "$MANIFEST" "${backup_dir}/manifest_$(timestamp).json"
  fi
  mv "$tmp" "$MANIFEST"
}

read_registry() {
  if [[ ! -f "$REGISTRY" ]]; then
    die "registry.json not found at $REGISTRY. Run meta-skill installer first."
  fi
  cat "$REGISTRY"
}

write_registry() {
  local tmp="${REGISTRY}.tmp.$$"
  cat > "$tmp"
  if [[ -f "$REGISTRY" ]]; then
    local backup_dir="${META_HOME}/backups"
    mkdir -p "$backup_dir"
    cp "$REGISTRY" "${backup_dir}/registry_$(timestamp).json"
  fi
  mv "$tmp" "$REGISTRY"
}

# ---- per-skill manifest ----

# Read a single skill's manifest entry from manifests/<name>.json.
# Returns empty string if the file does not exist (soft read).
read_skill_manifest() {
  local name="$1"
  local file="${MANIFESTS_DIR}/${name}.json"
  if [[ ! -f "$file" ]]; then
    return 0
  fi
  cat "$file"
}

# Write a single skill's manifest entry (from stdin) to manifests/<name>.json.
# Also ensures the skill is registered in the manifest.json index.
write_skill_manifest() {
  local name="$1"
  mkdir -p "$MANIFESTS_DIR"
  local file="${MANIFESTS_DIR}/${name}.json"
  local tmp="${file}.tmp.$$"
  cat > "$tmp"
  if [[ -f "$file" ]]; then
    local backup_dir="${META_HOME}/backups"
    mkdir -p "$backup_dir"
    cp "$file" "${backup_dir}/skill_${name}_$(timestamp).json"
  fi
  mv "$tmp" "$file"
  # Ensure skill is in the index
  if [[ -f "$MANIFEST" ]]; then
    read_manifest | jq --arg name "$name" '.skills[$name] = {}' | write_manifest
  fi
}

# Remove a skill's manifest file and delete it from the manifest.json index.
remove_skill_manifest() {
  local name="$1"
  local file="${MANIFESTS_DIR}/${name}.json"
  if [[ -f "$file" ]]; then
    rm "$file"
  fi
  if [[ -f "$MANIFEST" ]]; then
    read_manifest | jq --arg name "$name" 'del(.skills[$name])' | write_manifest
  fi
}

# ---- git with timeout ----

# Wraps git network operations with timeout protection.
# - HTTP: aborts on <1KB/s for 30s (git -c http.lowSpeedLimit/Time)
# - SSH: 10s ConnectTimeout
# - Shell watchdog: kills the process if it exceeds META_SKILL_GIT_TIMEOUT (default 300s)
git_with_timeout() {
  local timeout_sec="${META_SKILL_GIT_TIMEOUT:-300}"
  GIT_SSH_COMMAND="ssh -o ConnectTimeout=10" \
  git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=30 \
    "$@" &
  local pid=$!
  (
    sleep "$timeout_sec"
    kill $pid 2>/dev/null
  ) &
  local watchdog=$!
  wait $pid 2>/dev/null
  local rc=$?
  kill $watchdog 2>/dev/null
  wait $watchdog 2>/dev/null
  if [[ $rc -ne 0 ]]; then
    # Check if killed by timeout
    if ! kill -0 $pid 2>/dev/null && [[ $rc -eq 143 ]]; then
      die "Git operation timed out after ${timeout_sec}s"
    fi
  fi
  return $rc
}

# ---- misc helpers ----

timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

expand_path() {
  local p="$1"
  echo "${p/#\~/$HOME}"
}

detect_source_type() {
  local url="$1"
  if [[ "$url" == *"github.com/skillhub/"* ]]; then
    echo "skillhub"
  elif [[ "$url" == *"github.com"* ]] || [[ "$url" == git@* ]]; then
    echo "github"
  else
    echo "local"
  fi
}

# ---- source resolution ----

# Walk up from a directory to find the nearest git root.
# Outputs the absolute path of the git root, or returns 1 if not found.
find_git_root() {
  local dir
  dir=$(cd "$1" 2>/dev/null && pwd) || return 1
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/.git" ]]; then
      echo "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

# Normalize a git URL to HTTPS form.
#   git@github.com:user/repo.git → https://github.com/user/repo
#   ssh://git@github.com/user/repo → https://github.com/user/repo
#   Already HTTPS → pass through
normalize_git_url() {
  local url="$1"
  # Strip trailing .git
  url="${url%.git}"
  # SSH short form: git@host:path
  if [[ "$url" =~ ^git@([^:]+):(.+)$ ]]; then
    echo "https://${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
  # SSH full form: ssh://git@host/path
  elif [[ "$url" =~ ^ssh://git@([^/]+)/(.+)$ ]]; then
    echo "https://${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
  else
    echo "$url"
  fi
}

# Try to read source URL from a skill directory's own metadata.
# Checks (in priority order):
#   1. metadata.json → .source / .github / .url
#   2. SKILL.md frontmatter → source: / github: / url:
# Returns the URL string, or empty if nothing found.
read_skill_metadata_source() {
  local dir="$1"

  # 1. metadata.json
  if [[ -f "$dir/metadata.json" ]]; then
    local val
    val=$(jq -r '.source // .github // .url // empty' "$dir/metadata.json" 2>/dev/null)
    if [[ -n "$val" && "$val" != "null" ]]; then
      echo "$val"
      return 0
    fi
  fi

  # 2. SKILL.md frontmatter (YAML between --- markers)
  if [[ -f "$dir/SKILL.md" ]]; then
    local frontmatter
    frontmatter=$(sed -n '/^---$/,/^---$/p' "$dir/SKILL.md" 2>/dev/null)
    if [[ -n "$frontmatter" ]]; then
      local val
      # Try source:, github:, url: fields
      val=$(echo "$frontmatter" | grep -im1 '^source:' | sed 's/^[^:]*:[[:space:]]*//' | head -1)
      [[ -z "$val" ]] && val=$(echo "$frontmatter" | grep -im1 '^github:' | sed 's/^[^:]*:[[:space:]]*//' | head -1)
      [[ -z "$val" ]] && val=$(echo "$frontmatter" | grep -im1 '^url:' | sed 's/^[^:]*:[[:space:]]*//' | head -1)
      # Strip surrounding quotes and whitespace
      val=$(echo "$val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//;s/^'\''//;s/'\''$//')
      if [[ -n "$val" ]]; then
        echo "$val"
        return 0
      fi
    fi
  fi

  return 1
}

# Resolve the best source for a skill given its on-disk path.
# Priority: explicit --source > skill metadata > git remote origin > local path fallback
# Outputs: source_type source_url version subpath
resolve_source() {
  local target="$1"
  local explicit_source="${2:-}"

  # Priority 1: explicit --source
  if [[ -n "$explicit_source" ]]; then
    local stype
    stype=$(detect_source_type "$explicit_source")
    echo "$stype" "$explicit_source" "explicit" ""
    return 0
  fi

  local git_root subpath

  # Try to find a git root
  git_root=$(find_git_root "$target" 2>/dev/null || echo "")

  if [[ -n "$git_root" ]]; then
    # Calculate subpath relative to git root
    local target_abs
    target_abs=$(cd "$target" 2>/dev/null && pwd || echo "$target")
    if [[ "$target_abs" == "$git_root"* ]]; then
      subpath="${target_abs#$git_root}"
      subpath="${subpath#/}"
    fi

    # Priority 2: skill metadata
    local meta_url
    if [[ -n "$subpath" ]]; then
      meta_url=$(read_skill_metadata_source "${git_root}/${subpath}" 2>/dev/null || echo "")
    fi
    if [[ -z "$meta_url" ]]; then
      meta_url=$(read_skill_metadata_source "$git_root" 2>/dev/null || echo "")
    fi
    if [[ -n "$meta_url" ]]; then
      local stype sversion
      stype=$(detect_source_type "$meta_url")
      sversion=$(cd "$git_root" && git rev-parse --short HEAD 2>/dev/null || echo "unknown")
      echo "$stype" "$meta_url" "$sversion" "$subpath"
      return 0
    fi

    # Priority 3: git remote origin (normalized)
    local remote_url
    remote_url=$(cd "$git_root" && git remote get-url origin 2>/dev/null || echo "")
    if [[ -n "$remote_url" ]]; then
      remote_url=$(normalize_git_url "$remote_url")
      local stype sversion
      stype=$(detect_source_type "$remote_url")
      sversion=$(cd "$git_root" && git rev-parse --short HEAD 2>/dev/null || echo "unknown")
      echo "$stype" "$remote_url" "$sversion" "$subpath"
      return 0
    fi
  fi

  # Priority 4: local fallback
  local sversion
  sversion="local-$(timestamp)"
  echo "local" "$target" "$sversion" ""
}

# ---- agent / project linking ----

link_to_agent() {
  local skill_name="$1"
  local agent="$2"

  local agent_dir
  agent_dir=$(read_registry | jq -r ".agents[\"$agent\"].skill_dir // empty")
  if [[ -z "$agent_dir" ]]; then
    warn "Unknown agent: $agent. Skipping agent link."
    return 1
  fi

  agent_dir=$(expand_path "$agent_dir")
  mkdir -p "$agent_dir"

  local link_path="${agent_dir}/${skill_name}"
  if [[ -e "$link_path" ]]; then
    warn "Link already exists at $link_path, skipping"
    return 0
  fi

  ln -s "${SKILLS_DIR}/${skill_name}" "$link_path"
  info "Linked to agent '$agent' at $link_path"

  read_skill_manifest "$skill_name" | jq --arg agent "$agent" \
    '.agents += [$agent] | .agents |= unique' | write_skill_manifest "$skill_name"
}

link_to_project() {
  local skill_name="$1"
  local project="$2"

  if [[ ! -d "$project" ]]; then
    warn "Project directory not found: $project. Skipping project link."
    return 1
  fi

  local agents_info
  agents_info=$(read_registry | jq -r '.agents | to_entries[] | "\(.key) \(.value.project_skill_dir // empty)"')

  while IFS=' ' read -r agent project_skill_dir; do
    [[ -z "$agent" || -z "$project_skill_dir" ]] && continue
    local full_path="${project}/${project_skill_dir#./}"

    if [[ -d "$full_path" ]]; then
      local link_path="${full_path}/${skill_name}"
      if [[ -e "$link_path" ]]; then
        warn "Link already exists at $link_path, skipping"
        continue
      fi
      mkdir -p "$full_path"
      ln -s "${SKILLS_DIR}/${skill_name}" "$link_path"
      info "Linked to project '$project' ($agent) at $link_path"

      read_skill_manifest "$skill_name" | jq --arg project "$project" --arg agent "$agent" \
        '.projects[$project] += [$agent] | .projects[$project] |= unique' | write_skill_manifest "$skill_name"
    fi
  done <<< "$agents_info"
}

unlink_from_agent() {
  local skill_name="$1"
  local agent="$2"

  local agent_dir
  agent_dir=$(read_registry | jq -r ".agents[\"$agent\"].skill_dir // empty")
  if [[ -z "$agent_dir" ]]; then
    warn "Unknown agent: $agent"
    return 1
  fi

  agent_dir=$(expand_path "$agent_dir")
  local link_path="${agent_dir}/${skill_name}"

  if [[ -L "$link_path" ]]; then
    rm "$link_path"
    info "Removed agent link: $link_path"
  elif [[ -e "$link_path" ]]; then
    warn "$link_path exists but is not a symlink. Skipping (not managed by meta-skill)."
  fi

  read_skill_manifest "$skill_name" | jq --arg agent "$agent" \
    '.agents -= [$agent]' | write_skill_manifest "$skill_name"
}

unlink_from_project() {
  local skill_name="$1"
  local project="$2"

  if [[ ! -d "$project" ]]; then
    warn "Project directory not found: $project"
    return 1
  fi

  local agents_info
  agents_info=$(read_registry | jq -r '.agents | to_entries[] | "\(.key) \(.value.project_skill_dir // empty)"')

  while IFS=' ' read -r agent project_skill_dir; do
    [[ -z "$agent" || -z "$project_skill_dir" ]] && continue
    local full_path="${project}/${project_skill_dir#./}"
    local link_path="${full_path}/${skill_name}"
    if [[ -L "$link_path" ]]; then
      rm "$link_path"
      info "Removed project link: $link_path"
    fi
  done <<< "$agents_info"

  read_skill_manifest "$skill_name" | jq --arg project "$project" \
    'del(.projects[$project])' | write_skill_manifest "$skill_name"
}
