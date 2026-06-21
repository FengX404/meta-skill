#!/usr/bin/env bash
# list-skills.sh — List all managed skills from manifest
# Usage: list-skills.sh [--agent <a>] [--project <p>] [--detail]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

main() {
  local target_agent=""
  local target_project=""
  local detail=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --agent)   target_agent="$2"; shift 2 ;;
      --project) target_project="$2"; shift 2 ;;
      --detail)  detail=true; shift ;;
      *) shift ;;
    esac
  done

  local manifest_data
  manifest_data=$(read_manifest)

  local total
  total=$(echo "$manifest_data" | jq '.skills | length')
  info "Skills managed: $total"
  echo

  local names
  names=$(echo "$manifest_data" | jq -r '.skills | keys[]')

  # Filter names by agent/project if requested
  local filtered_names=()
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    local entry
    entry=$(read_skill_manifest "$name")
    local match=true

    if [[ -n "$target_agent" ]]; then
      local has_agent
      has_agent=$(echo "$entry" | jq -r --arg agent "$target_agent" '.agents | contains([$agent])')
      [[ "$has_agent" != "true" ]] && match=false
    fi

    if [[ -n "$target_project" ]]; then
      local has_project
      has_project=$(echo "$entry" | jq -r --arg project "$target_project" '.projects | has($project)')
      [[ "$has_project" != "true" ]] && match=false
    fi

    if $match; then
      filtered_names+=("$name")
    fi
  done <<< "$names"

  echo

  if $detail; then
    for name in "${filtered_names[@]}"; do
      local entry
      entry=$(read_skill_manifest "$name")
      echo "--- $name ---"
      echo "$entry" | jq '{source: .source, installed_at, updated_at, agents, projects: (.projects | keys)}'
      echo
    done
  else
    printf "%-20s %-12s %-12s %-25s %s\n" "NAME" "SOURCE" "VERSION" "AGENTS" "PROJECTS"
    printf "%s\n" "$(printf '%.0s-' {1..100})"

    if [[ ${#filtered_names[@]} -eq 0 ]]; then
      echo "  (no skills matching filters)"
    else
      for name in "${filtered_names[@]}"; do
        local entry
        entry=$(read_skill_manifest "$name")
        local src_type version agents projects
        src_type=$(echo "$entry" | jq -r '.source.type')
        version=$(echo "$entry" | jq -r '.source.version')
        agents=$(echo "$entry" | jq -r '(.agents | join(",")) // "-"')
        projects=$(echo "$entry" | jq -r '(.projects | keys | join(",")) // "-"')
        printf "%-20s %-12s %-12s %-25s %s\n" "$name" "$src_type" "${version:0:7}" "${agents:--}" "${projects:--}"
      done
    fi
  fi

  # Integrity check
  echo
  info "Integrity check..."
  local issues=0

  for dir in "$SKILLS_DIR"/*/; do
    [[ ! -d "$dir" ]] && continue
    local dname
    dname=$(basename "$dir")
    local in_manifest
    in_manifest=$(echo "$manifest_data" | jq -r ".skills | has(\"$dname\")")
    if [[ "$in_manifest" == "false" ]]; then
      warn "Orphan directory (not in manifest): $dir"
      ((issues++)) || true
    fi
  done

  # Check per-skill manifest files vs index consistency
  if [[ -d "$MANIFESTS_DIR" ]]; then
    for mfile in "$MANIFESTS_DIR"/*.json; do
      [[ ! -f "$mfile" ]] && continue
      local mname
      mname=$(basename "$mfile" .json)
      local in_index
      in_index=$(echo "$manifest_data" | jq -r --arg name "$mname" '.skills | has($name)')
      if [[ "$in_index" == "false" ]]; then
        warn "Orphan manifest file (not in index): $mfile"
        ((issues++)) || true
      fi
    done
  fi

  local agents_json
  agents_json=$(read_registry | jq -r '.agents | keys[]')
  while IFS= read -r agent; do
    local agent_dir
    agent_dir=$(expand_path "$(read_registry | jq -r ".agents[\"$agent\"].skill_dir // empty")")
    if [[ -d "$agent_dir" ]]; then
      for link in "$agent_dir"/*; do
        if [[ -L "$link" ]] && [[ ! -e "$link" ]]; then
          warn "Broken symlink in $agent: $link"
          ((issues++)) || true
        fi
      done
    fi
  done <<< "$agents_json"

  if [[ $issues -eq 0 ]]; then
    info "All checks passed."
  else
    warn "$issues issue(s) found. Run 'meta-skill sync' to fix."
  fi
}

main "$@"
