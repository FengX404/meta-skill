#!/usr/bin/env bash
# import-skill.sh — Import an existing (unmanaged) skill into meta-skill management
# Usage: import-skill.sh <name> [--source <url>] [--agent <a>] [--project <p>] [--all] [--orphan] [--dry-run]
#
# Import strategies based on what scan found:
#   unmanaged-symlink  → clone/copy target to ~/.meta-skill/skills/<name>/, update symlink
#   unmanaged-directory → move to ~/.meta-skill/skills/<name>/, create symlink in place
#   orphan              → register existing dir in manifest, create symlinks
#
# Edge cases:
#   - Name conflict with existing managed skill → error, suggest rename
#   - Source unreachable (symlink target gone) → error, suggest --source to specify new source
#   - Duplicate symlinks → keep the first one found, warn about others

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

# ---- discovery ----

# Find the first occurrence of a skill by name across agents
# Returns JSON: {agent, path, kind, target, location_type, project}
find_skill() {
  local name="$1"
  local manifest_data
  manifest_data=$(read_manifest)

  local all_agents
  all_agents=$(echo "$manifest_data" | jq -r '.agents | keys[]')

  while IFS= read -r agent; do
    if [[ -z "$agent" ]]; then continue; fi
    local home_dir
    home_dir=$(expand_path "$(echo "$manifest_data" | jq -r ".agents[\"$agent\"].home // empty")")
    [[ ! -d "$home_dir" ]] && continue

    local skill_dir
    skill_dir=$(expand_path "$(echo "$manifest_data" | jq -r ".agents[\"$agent\"].skill_dir // empty")")
    [[ ! -d "$skill_dir" ]] && continue

    local entry_path="${skill_dir}/${name}"

    if [[ -L "$entry_path" ]]; then
      if [[ -e "$entry_path" ]]; then
        local target
        target=$(readlink "$entry_path")
        if [[ "$target" != "${SKILLS_DIR}/"* ]]; then
          jq -n --arg agent "$agent" --arg path "$entry_path" --arg kind "symlink" --arg target "$target" --arg location_type "agent" --arg project "" \
            '{agent: $agent, path: $path, kind: $kind, target: $target, location_type: $location_type, project: $project}'
          return 0
        fi
      fi
    elif [[ -d "$entry_path" ]]; then
      jq -n --arg agent "$agent" --arg path "$entry_path" --arg kind "directory" --arg target "" --arg location_type "agent" --arg project "" \
        '{agent: $agent, path: $path, kind: $kind, target: $target, location_type: $location_type, project: $project}'
      return 0
    fi
  done <<< "$all_agents"

  return 1
}

# Check if skill is an orphan in ~/.meta-skill/skills/
find_orphan() {
  local name="$1"
  local dir="${SKILLS_DIR}/${name}"

  if [[ -d "$dir" ]]; then
    local manifest_data
    manifest_data=$(read_manifest)
    local in_manifest
    in_manifest=$(echo "$manifest_data" | jq -r ".skills | has(\"$name\")")

    if [[ "$in_manifest" == "false" ]]; then
      echo "$dir"
      return 0
    fi
  fi

  return 1
}

# ---- import strategies ----

import_symlink() {
  local name="$1" target="$2" agent="$3"
  local explicit_source="${4:-}"

  local dest="${SKILLS_DIR}/${name}"

  if [[ -d "$dest" ]]; then
    die "Destination already exists: $dest. Remove it first or use a different name."
  fi

  # Resolve source info (handles git root walk, subpath, metadata, SSH normalization)
  local source_type source_url version subpath
  read -r source_type source_url version subpath <<< "$(resolve_source "$target" "$explicit_source")"

  local git_root
  git_root=$(find_git_root "$target" 2>/dev/null || echo "")

  if [[ -n "$git_root" ]] && [[ -n "$subpath" ]]; then
    # Target is a subdirectory of a git repo: clone the whole repo, symlink the subdir
    info "Target is subdirectory of git repo ($git_root). Cloning repo, linking subpath '$subpath'..."
    local repo_dest="${SKILLS_DIR}/_repo_${name}"
    if [[ -d "$repo_dest" ]]; then
      rm -rf "$repo_dest"
    fi
    if ! git clone "$git_root" "$repo_dest" 2>/dev/null; then
      die "Failed to clone $git_root"
    fi
    local subdir_dest="${repo_dest}/${subpath}"
    if [[ ! -d "$subdir_dest" ]]; then
      rm -rf "$repo_dest"
      die "Subpath '$subpath' not found in cloned repo"
    fi
    ln -s "$subdir_dest" "$dest"
    info "Linked subdirectory: $dest → $subdir_dest"
  elif [[ -d "${target}/.git" ]]; then
    # Target is itself a git repo
    info "Target is a git repository. Cloning..."
    if ! git clone "$target" "$dest" 2>/dev/null; then
      die "Failed to clone $target to $dest"
    fi
  else
    # Plain directory
    info "Copying directory contents..."
    mkdir -p "$dest"
    if ! cp -R "${target}/"* "$dest/" 2>/dev/null; then
      die "Failed to copy $target to $dest"
    fi
  fi

  # Get version from the actual managed directory (not the clone dest for subpath case)
  if [[ -n "$git_root" ]] && [[ -n "$subpath" ]]; then
    # Version already resolved from git_root by resolve_source
    :
  elif [[ -d "${dest}/.git" ]]; then
    version=$(cd "$dest" && git rev-parse --short HEAD 2>/dev/null || echo "unknown")
  fi

  echo "$source_type" "$source_url" "$version" "$subpath"
}

import_directory() {
  local name="$1" path="$2" agent="$3"
  local explicit_source="${4:-}"

  local dest="${SKILLS_DIR}/${name}"

  if [[ -d "$dest" ]]; then
    die "Destination already exists: $dest. Remove it first or use a different name."
  fi

  # Resolve source before moving (path will change after move)
  local source_type source_url version subpath
  read -r source_type source_url version subpath <<< "$(resolve_source "$path" "$explicit_source")"

  # If it's part of a git repo with a remote, clone instead of moving
  local git_root
  git_root=$(find_git_root "$path" 2>/dev/null || echo "")

  if [[ -n "$git_root" ]] && [[ "$source_type" != "local" ]]; then
    info "Directory belongs to git repo ($git_root). Cloning with subpath '$subpath'..."
    local repo_dest="${SKILLS_DIR}/_repo_${name}"
    if [[ -d "$repo_dest" ]]; then
      rm -rf "$repo_dest"
    fi
    if ! git clone "$git_root" "$repo_dest" 2>/dev/null; then
      die "Failed to clone $git_root"
    fi
    local subdir_dest="${repo_dest}/${subpath}"
    if [[ ! -d "$subdir_dest" ]]; then
      rm -rf "$repo_dest"
      die "Subpath '$subpath' not found in cloned repo"
    fi
    ln -s "$subdir_dest" "$dest"
    info "Linked subdirectory: $dest → $subdir_dest"
    # Remove original directory since we cloned from git
    rm -rf "$path"
    info "Removed original directory: $path"
  else
    info "Moving local directory to central repository..."
    mv "$path" "$dest"
    info "Moved: $path → $dest"
  fi

  echo "$source_type" "$source_url" "$version" "$subpath"
}

import_orphan() {
  local name="$1"

  local dest="${SKILLS_DIR}/${name}"

  if [[ ! -d "$dest" ]]; then
    die "No orphan directory found for '$name' in ~/.meta-skill/skills/"
  fi

  info "Registering orphan directory: $dest"

  # Resolve source from the existing directory
  local source_type source_url version subpath
  read -r source_type source_url version subpath <<< "$(resolve_source "$dest" "")"

  echo "$source_type" "$source_url" "$version" "$subpath"
}

# Register skill in manifest
register_in_manifest() {
  local name="$1" source_type="$2" source_url="$3" version="$4" subpath="${5:-}"

  local now
  now=$(timestamp)

  local source_json
  if [[ -n "$subpath" ]]; then
    source_json=$(jq -n \
      --arg type "$source_type" \
      --arg url "$source_url" \
      --arg version "$version" \
      --arg subpath "$subpath" \
      '{type: $type, url: $url, version: $version, subpath: $subpath}')
  else
    source_json=$(jq -n \
      --arg type "$source_type" \
      --arg url "$source_url" \
      --arg version "$version" \
      '{type: $type, url: $url, version: $version}')
  fi

  read_manifest | jq \
    --arg name "$name" \
    --argjson source "$source_json" \
    --arg now "$now" \
    '.skills[$name] = {
      source: $source,
      agents: [],
      projects: {},
      installed_at: $now,
      updated_at: $now
    }' | write_manifest

  info "Registered '$name' in manifest"
}

# ---- main ----

main() {
  local skill_name=""
  local source_url=""
  local target_agents=()
  local target_projects=()
  local link_all=false
  local is_orphan=false
  local dry_run=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --source)
        source_url="$2"
        shift 2
        ;;
      --agent)
        target_agents+=("$2")
        shift 2
        ;;
      --project)
        target_projects+=("$2")
        shift 2
        ;;
      --all)
        link_all=true
        shift
        ;;
      --orphan)
        is_orphan=true
        shift
        ;;
      --dry-run)
        dry_run=true
        shift
        ;;
      -*)
        shift
        ;;
      *)
        if [[ -z "$skill_name" ]]; then
          skill_name="$1"
        fi
        shift
        ;;
    esac
  done

  if [[ -z "$skill_name" ]]; then
    die "Skill name required. Usage: import-skill.sh <name> [--source <url>] [--agent <a>] [--all] [--orphan] [--dry-run]"
  fi

  # Check if already managed
  local manifest_data
  manifest_data=$(read_manifest)
  local already_managed
  already_managed=$(echo "$manifest_data" | jq -r ".skills | has(\"$skill_name\")")

  if [[ "$already_managed" == "true" ]]; then
    die "Skill '$skill_name' is already managed by meta-skill. Use 'meta-skill list' to see details."
  fi

  local source_type=""
  local version=""
  local subpath=""
  local found_agent=""

  # --- Determine import strategy ---

  if $is_orphan; then
    # Import orphan directory
    info "Importing orphan: $skill_name"
    if $dry_run; then
      info "[DRY RUN] Would register orphan directory ~/.meta-skill/skills/$skill_name in manifest"
      echo "  source_type=local, source_url=~/.meta-skill/skills/$skill_name"
      exit 0
    fi

    local import_result
    import_result=$(import_orphan "$skill_name")
    read -r source_type source_url version subpath <<< "$import_result"

    register_in_manifest "$skill_name" "$source_type" "$source_url" "$version" "$subpath"

  else
    # Find the skill in agent directories
    local found
    found=$(find_skill "$skill_name")

    if [[ -z "$found" ]]; then
      # Check if it's an orphan
      local orphan_dir
      orphan_dir=$(find_orphan "$skill_name")
      if [[ -n "$orphan_dir" ]]; then
        info "Skill '$skill_name' found as orphan in ~/.meta-skill/skills/. Use --orphan to import."
        die "Use 'meta-skill import $skill_name --orphan' to register the orphan directory."
      fi
      die "Skill '$skill_name' not found in any agent directory. Run 'meta-skill scan' to discover skills."
    fi

    local kind path target agent location_type project
    kind=$(echo "$found" | jq -r '.kind')
    path=$(echo "$found" | jq -r '.path')
    target=$(echo "$found" | jq -r '.target')
    agent=$(echo "$found" | jq -r '.agent')
    location_type=$(echo "$found" | jq -r '.location_type')
    project=$(echo "$found" | jq -r '.project')

    found_agent="$agent"

    if $dry_run; then
      info "[DRY RUN] Would import '$skill_name' from $location_type '$agent'"
      echo "  kind=$kind, path=$path, target=$target"
      exit 0
    fi

    # Execute import based on kind
    local import_result
    case "$kind" in
      symlink)
        info "Importing unmanaged symlink: $path → $target"
        import_result=$(import_symlink "$skill_name" "$target" "$agent" "$source_url")
        ;;
      directory)
        info "Importing unmanaged directory: $path"
        import_result=$(import_directory "$skill_name" "$path" "$agent" "$source_url")
        ;;
      *)
        die "Unknown kind: $kind. Cannot import."
        ;;
    esac

    read -r source_type source_url version subpath <<< "$import_result"

    # Register in manifest
    register_in_manifest "$skill_name" "$source_type" "$source_url" "$version" "$subpath"
  fi

  # --- Create symlinks ---

  # Determine which agents to link to
  local link_agents=()

  if $link_all; then
    # Link to all agents with existing home dirs
    local all_agents
    all_agents=$(echo "$manifest_data" | jq -r '.agents | keys[]')
    while IFS= read -r a; do
      if [[ -n "$a" ]]; then
        local home_dir
        home_dir=$(expand_path "$(echo "$manifest_data" | jq -r ".agents[\"$a\"].home // empty")")
        if [[ -d "$home_dir" ]]; then
          link_agents+=("$a")
        fi
      fi
    done <<< "$all_agents"
  elif [[ ${#target_agents[@]} -gt 0 ]]; then
    link_agents=("${target_agents[@]}")
  elif [[ -n "$found_agent" ]]; then
    # Default: link only to the agent where the skill was found
    link_agents=("$found_agent")
  fi

  for a in "${link_agents[@]}"; do
    link_to_agent "$skill_name" "$a" || true
  done

  # Link to projects if specified
  for p in "${target_projects[@]}"; do
    link_to_project "$skill_name" "$p" || true
  done

  # Remove the old symlink/directory we imported from (only if it was in an agent dir)
  if [[ "$is_orphan" != "true" ]] && [[ -n "$path" ]]; then
    if [[ "$kind" == "symlink" ]]; then
      rm -f "$path"
      info "Removed old symlink: $path"
    fi
    # For directories, they were already moved by import_directory()
  fi

  # Check for duplicates — warn about other unmanaged instances of the same skill
  info "Checking for other instances of '$skill_name'..."
  local dup_count=0
  local all_agents2
  all_agents2=$(echo "$manifest_data" | jq -r '.agents | keys[]')
  while IFS= read -r a; do
    if [[ -z "$a" ]]; then continue; fi
    local skill_dir
    skill_dir=$(expand_path "$(echo "$manifest_data" | jq -r ".agents[\"$a\"].skill_dir // empty")")
    local entry="${skill_dir}/${skill_name}"
    if [[ -L "$entry" ]] && [[ -e "$entry" ]]; then
      local t
      t=$(readlink "$entry")
      if [[ "$t" != "${SKILLS_DIR}/${skill_name}" ]]; then
        warn "Duplicate found: $a has $skill_name → $t (now managed at ${SKILLS_DIR}/${skill_name}). Run 'meta-skill install $skill_name --agent $a' to replace."
        ((dup_count++)) || true
      fi
    elif [[ -d "$entry" ]] && [[ "$entry" != "${SKILLS_DIR}/${skill_name}" ]]; then
      warn "Local copy found: $a has $skill_name as a directory. Consider removing it manually."
      ((dup_count++)) || true
    fi
  done <<< "$all_agents2"

  if [[ $dup_count -eq 0 ]]; then
    info "No duplicates found."
  fi

  info "Import complete: $skill_name (source: $source_type, agents: ${link_agents[*]})"
}

main "$@"
