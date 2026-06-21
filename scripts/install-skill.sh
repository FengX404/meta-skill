#!/usr/bin/env bash
# install-skill.sh — Install a skill from a source into ~/.meta-skill/skills/
# Usage: install-skill.sh <name> --source <url> [--all] [--agent <a>] [--project <p>]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

main() {
  local skill_name=""
  local source=""
  local agents=()
  local projects=()
  local install_all=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --source)  source="$2"; shift 2 ;;
      --agent)   agents+=("$2"); shift 2 ;;
      --project) projects+=("$2"); shift 2 ;;
      --all)     install_all=true; shift ;;
      *) skill_name="$1"; shift ;;
    esac
  done

  [[ -z "$skill_name" ]] && die "skill name required"
  [[ -z "$source" ]] && die "--source <url|path> required"

  local source_type
  source_type=$(detect_source_type "$source")

  info "Installing skill: $skill_name (source: $source_type)"

  local dest="${SKILLS_DIR}/${skill_name}"
  if [[ -d "$dest" ]]; then
    die "Skill '$skill_name' already exists at $dest"
  fi

  mkdir -p "$SKILLS_DIR"

  # Fetch skill from source
  case "$source_type" in
    github|skillhub)
      info "Cloning from $source ..."
      git_with_timeout clone "$source" "$dest" || die "Failed to clone $source"
      local version
      version=$(cd "$dest" && git rev-parse HEAD)
      ;;
    local)
      if [[ ! -d "$source" ]]; then
        die "Local source directory not found: $source"
      fi
      info "Copying from $source ..."
      cp -r "$source" "$dest"
      local version="local-$(timestamp)"
      ;;
  esac

  # Register in manifest
  local entry
  entry=$(jq -n \
    --arg name "$skill_name" \
    --arg type "$source_type" \
    --arg url "$source" \
    --arg version "$version" \
    --arg installed_at "$(timestamp)" \
    --arg updated_at "$(timestamp)" \
    '{
      source: { type: $type, url: $url, version: $version },
      installed_at: $installed_at,
      updated_at: $updated_at,
      agents: [],
      projects: {}
    }')

  echo "$entry" | write_skill_manifest "$skill_name"
  info "Registered in manifest"

  # --all: link to all agents whose home directory exists
  if $install_all; then
    info "Linking to all installed agents..."
    local all_agents
    all_agents=$(read_registry | jq -r '.agents | to_entries[] | "\(.key) \(.value.home)"')
    while IFS=' ' read -r agent_key home_raw; do
      [[ -z "$agent_key" ]] && continue
      local home_dir
      home_dir=$(eval echo "$home_raw")
      if [[ -d "$home_dir" ]]; then
        link_to_agent "$skill_name" "$agent_key"
      else
        info "  Skipping $agent_key (not installed)"
      fi
    done <<< "$all_agents"
  else
    if [[ ${#agents[@]} -gt 0 ]]; then
      for agent in "${agents[@]}"; do
        link_to_agent "$skill_name" "$agent"
      done
    fi
  fi

  # Link to projects
  if [[ ${#projects[@]} -gt 0 ]]; then
    for project in "${projects[@]}"; do
      link_to_project "$skill_name" "$project"
    done
  fi

  info "Skill '$skill_name' installed successfully"
}

main "$@"
