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

  local query='.skills | to_entries[]'

  if [[ -n "$target_agent" ]]; then
    query+=" | select(.value.agents | contains([\"$target_agent\"]))"
    echo "Filtered by agent: $target_agent"
  fi

  if [[ -n "$target_project" ]]; then
    query+=" | select(.value.projects | has(\"$target_project\"))"
    echo "Filtered by project: $target_project"
  fi

  echo

  if $detail; then
    local data
    data=$(echo "$manifest_data" | jq -r "$query | \"\(.key)\"")
    for name in $data; do
      local entry
      entry=$(echo "$manifest_data" | jq ".skills[\"$name\"]")
      echo "--- $name ---"
      echo "$entry" | jq '{source: .source, installed_at, updated_at, agents, projects: (.projects | keys)}'
      echo
    done
  else
    printf "%-20s %-12s %-12s %-25s %s\n" "NAME" "SOURCE" "VERSION" "AGENTS" "PROJECTS"
    printf "%s\n" "$(printf '%.0s-' {1..100})"

    local data
    data=$(echo "$manifest_data" | jq -r "$query | \"\(.key)|\(.value.source.type)|\(.value.source.version[0:7])|\((.value.agents | join(\",\")) // \"-\")|\((.value.projects | keys | join(\",\")) // \"-\")\"")

    if [[ -z "$data" ]]; then
      echo "  (no skills matching filters)"
    else
      while IFS='|' read -r name src_type version agents projects; do
        printf "%-20s %-12s %-12s %-25s %s\n" "$name" "$src_type" "${version:0:7}" "${agents:--}" "${projects:--}"
      done <<< "$data"
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

  local agents_json
  agents_json=$(echo "$manifest_data" | jq -r '.agents | keys[]')
  while IFS= read -r agent; do
    local agent_dir
    agent_dir=$(expand_path "$(echo "$manifest_data" | jq -r ".agents[\"$agent\"].skill_dir // empty")")
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
