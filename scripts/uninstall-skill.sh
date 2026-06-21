#!/usr/bin/env bash
# uninstall-skill.sh — Uninstall a skill from ~/.meta-skill/skills/
# Usage: uninstall-skill.sh <name> [--agent <a>] [--project <p>]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

main() {
  local skill_name=""
  local target_agent=""
  local target_project=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --agent)   target_agent="$2"; shift 2 ;;
      --project) target_project="$2"; shift 2 ;;
      *) skill_name="$1"; shift ;;
    esac
  done

  [[ -z "$skill_name" ]] && die "skill name required"

  local entry
  entry=$(read_skill_manifest "$skill_name")
  if [[ -z "$entry" ]]; then
    die "Skill '$skill_name' not found in manifest"
  fi

  # Selective uninstall
  if [[ -n "$target_agent" ]]; then
    info "Removing skill '$skill_name' from agent '$target_agent'..."
    unlink_from_agent "$skill_name" "$target_agent"
    return
  fi

  if [[ -n "$target_project" ]]; then
    info "Removing skill '$skill_name' from project '$target_project'..."
    unlink_from_project "$skill_name" "$target_project"
    return
  fi

  # Full uninstall
  info "Uninstalling skill: $skill_name"

  local agent_count project_count
  agent_count=$(echo "$entry" | jq -r '.agents | length')
  project_count=$(echo "$entry" | jq -r '.projects | keys | length')
  info "This will remove: 1 skill directory, $agent_count agent link(s), $project_count project link(s)"

  # Unlink from all agents
  local agents_json
  agents_json=$(echo "$entry" | jq -r '.agents[]')
  while IFS= read -r agent; do
    if [[ -n "$agent" ]]; then
      unlink_from_agent "$skill_name" "$agent"
    fi
  done <<< "$agents_json"

  # Unlink from all projects
  local projects_json
  projects_json=$(echo "$entry" | jq -r '.projects | keys[]')
  while IFS= read -r project; do
    if [[ -n "$project" ]]; then
      unlink_from_project "$skill_name" "$project"
    fi
  done <<< "$projects_json"

  # Remove skill directory
  local dest="${SKILLS_DIR}/${skill_name}"
  if [[ -d "$dest" ]]; then
    rm -rf "$dest"
    info "Removed skill directory: $dest"
  elif [[ -L "$dest" ]]; then
    rm -f "$dest"
    info "Removed symlink: $dest"
  fi

  # Remove backing repo for subpath skills
  local repo_dest="${SKILLS_DIR}/_repo_${skill_name}"
  if [[ -d "$repo_dest" ]]; then
    rm -rf "$repo_dest"
    info "Removed backing repository: $repo_dest"
  fi

  # Remove from manifest
  remove_skill_manifest "$skill_name"
  info "Skill '$skill_name' fully uninstalled"
}

main "$@"
