#!/usr/bin/env bash
# scan-skills.sh — Discover all skills across agents, projects, and meta-skill repo
# Usage: scan-skills.sh [--agent <name>] [--project <path>] [--json] [--include-projects]
#
# Scans:
#   1. Agent global skill dirs (e.g. ~/.trae-cn/skills/*)
#   2. Meta-skill orphans (~/.meta-skill/skills/* not in manifest)
#   3. Project skill dirs (only if --project or --include-projects given)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

# ---- helpers ----

# Classify a filesystem entry in an agent skill dir
# Returns: managed | unmanaged-symlink | unmanaged-directory | broken-symlink | unknown
classify_entry() {
  local path="$1"

  if [[ -L "$path" ]]; then
    local target
    target=$(readlink "$path")
    if [[ ! -e "$path" ]]; then
      echo "broken-symlink"
    elif [[ "$target" == "${SKILLS_DIR}/"* ]]; then
      echo "managed"
    else
      echo "unmanaged-symlink"
    fi
  elif [[ -d "$path" ]]; then
    echo "unmanaged-directory"
  else
    echo "unknown"
  fi
}

# Output JSON for one finding
output_json_finding() {
  local name="$1" location_type="$2" agent="$3" project="$4" path="$5" kind="$6" status="$7" target="$8"
  jq -n \
    --arg name "$name" \
    --arg location_type "$location_type" \
    --arg agent "$agent" \
    --arg project "$project" \
    --arg path "$path" \
    --arg kind "$kind" \
    --arg status "$status" \
    --arg target "$target" \
    '{name: $name, location_type: $location_type, agent: $agent, project: $project, path: $path, kind: $kind, status: $status, target: $target}'
}

# ---- scanning functions ----

scan_agent_dir() {
  local agent="$1" agent_dir="$2" project="$3"
  local location_type="agent"
  [[ -n "$project" ]] && location_type="project"

  if [[ ! -d "$agent_dir" ]]; then
    return
  fi

  for entry in "$agent_dir"/*; do
    [[ ! -e "$entry" ]] && continue
    local name
    name=$(basename "$entry")
    local status
    status=$(classify_entry "$entry")
    local kind="directory"
    local target=""

    if [[ -L "$entry" ]]; then
      kind="symlink"
      target=$(readlink "$entry")
    fi

    findings+=("$(output_json_finding "$name" "$location_type" "$agent" "$project" "$entry" "$kind" "$status" "$target")")
  done
}

scan_orphans() {
  if [[ ! -d "$SKILLS_DIR" ]]; then
    return
  fi

  local manifest_data
  manifest_data=$(read_manifest)

  for dir in "$SKILLS_DIR"/*/; do
    [[ ! -d "$dir" ]] && continue
    local name
    name=$(basename "$dir")
    local in_manifest
    in_manifest=$(echo "$manifest_data" | jq -r ".skills | has(\"$name\")")

    if [[ "$in_manifest" == "false" ]]; then
      orphans+=("$(jq -n --arg name "$name" --arg path "$(echo "$dir" | sed 's|/$||')" '{name: $name, path: $path}')")
    fi
  done
}

scan_broken_links() {
  local registry_data
  registry_data=$(read_registry)

  local agents_json
  agents_json=$(echo "$registry_data" | jq -r '.agents | keys[]')
  while IFS= read -r agent; do
    if [[ -n "$agent" ]]; then
      local agent_dir
      agent_dir=$(expand_path "$(echo "$registry_data" | jq -r ".agents[\"$agent\"].skill_dir // empty")")
      if [[ -d "$agent_dir" ]]; then
        for link in "$agent_dir"/*; do
          if [[ -L "$link" ]] && [[ ! -e "$link" ]]; then
            local target
            target=$(readlink "$link" 2>/dev/null || echo "unknown")
            broken_links+=("$(jq -n --arg name "$(basename "$link")" --arg agent "$agent" --arg path "$link" --arg target "$target" '{name: $name, agent: $agent, path: $path, target: $target}')")
          fi
        done
      fi
    fi
  done <<< "$agents_json"
}

detect_duplicates() {
  local -a targets_seen=()
  local -a dup_indices=()

  for i in "${!findings[@]}"; do
    local entry="${findings[$i]}"
    local target
    target=$(echo "$entry" | jq -r '.target // empty')
    local status
    status=$(echo "$entry" | jq -r '.status')
    # Only consider unmanaged symlinks for dedup
    [[ "$status" != "unmanaged-symlink" ]] && continue
    [[ -z "$target" ]] && continue

    local already=-1
    local j
    for j in "${!targets_seen[@]}"; do
      if [[ "${targets_seen[$j]}" == "$target" ]]; then
        already=$j
        break
      fi
    done

    if [[ $already -ge 0 ]]; then
      dup_indices+=("$already" "$i")
    else
      targets_seen+=("$target")
    fi
  done

  # Mark duplicates in findings
  # (string-based lookup for bash 3.2 compatibility — no associative arrays)
  local dup_str=" "
  if [[ ${#dup_indices[@]} -gt 0 ]]; then
    for idx in "${dup_indices[@]}"; do
      dup_str+="$idx "
    done
  fi

  local new_findings=()
  for i in "${!findings[@]}"; do
    local entry="${findings[$i]}"
    if [[ "$dup_str" == *" $i "* ]]; then
      entry=$(echo "$entry" | jq '. + {duplicate: true}')
    fi
    new_findings+=("$entry")
  done
  if [[ ${#new_findings[@]} -gt 0 ]]; then
    findings=("${new_findings[@]}")
  fi
}

# ---- output formatters ----

output_table() {
  local manifest_data
  manifest_data=$(read_manifest)

  echo
  info "Skill Scan Report"
  echo

  # Count managed
  local managed_count=0
  for f in "${findings[@]}"; do
    [[ $(echo "$f" | jq -r '.status') == "managed" ]] && ((managed_count++)) || true
  done

  local total_managed
  total_managed=$(echo "$manifest_data" | jq '.skills | length')
  local dedicated_managed=$((managed_count > total_managed ? 0 : total_managed - managed_count))

  echo "Summary:"
  echo "  Managed (via meta-skill): $total_managed"
  echo "  Unmanaged symlinks:       $(count_by_status 'unmanaged-symlink')"
  echo "  Unmanaged directories:    $(count_by_status 'unmanaged-directory')"
  echo "  Broken symlinks:          ${#broken_links[@]}"
  echo "  Orphan dirs in repo:      ${#orphans[@]}"
  local dup_count
  dup_count=$(count_duplicates)
  echo "  Potential duplicates:     $dup_count"
  echo

  # Managed section
  if [[ $managed_count -gt 0 ]]; then
    echo "--- Managed (by meta-skill) ---"
    printf "  %-25s %-8s %-10s %s\n" "NAME" "TYPE" "AGENT" "PATH"
    for f in "${findings[@]}"; do
      [[ $(echo "$f" | jq -r '.status') != "managed" ]] && continue
      local name agent loctype path
      name=$(echo "$f" | jq -r '.name')
      agent=$(echo "$f" | jq -r '.agent // "-"')
      loctype=$(echo "$f" | jq -r '.location_type')
      path=$(echo "$f" | jq -r '.path')
      printf "  %-25s %-8s %-10s %s\n" "$name" "$loctype" "$agent" "$path"
    done
    echo
  fi

  # Unmanaged section
  local unmanaged_count
  unmanaged_count=$(count_by_status 'unmanaged-symlink')
  local unmanaged_dir_count
  unmanaged_dir_count=$(count_by_status 'unmanaged-directory')
  local total_unmanaged=$((unmanaged_count + unmanaged_dir_count))

  if [[ $total_unmanaged -gt 0 ]]; then
    echo "--- Unmanaged (candidates for import) ---"
    printf "  %-25s %-10s %-10s %-8s %s\n" "NAME" "TYPE" "AGENT" "KIND" "TARGET"
    for f in "${findings[@]}"; do
      local status
      status=$(echo "$f" | jq -r '.status')
      [[ "$status" != "unmanaged-symlink" && "$status" != "unmanaged-directory" ]] && continue
      local name agent loctype kind target dup
      name=$(echo "$f" | jq -r '.name')
      agent=$(echo "$f" | jq -r '.agent // "-"')
      loctype=$(echo "$f" | jq -r '.location_type')
      kind=$(echo "$f" | jq -r '.kind')
      target=$(echo "$f" | jq -r '.target // "(local directory)"')
      dup=$(echo "$f" | jq -r '.duplicate // false')
      local marker=""
      [[ "$dup" == "true" ]] && marker=" [DUP]"
      printf "  %-25s %-10s %-10s %-8s %s%s\n" "$name" "$loctype" "$agent" "$kind" "$target" "$marker"
    done
    echo
  fi

  # Broken links
  if [[ ${#broken_links[@]} -gt 0 ]]; then
    echo "--- Broken Symlinks (fix with: meta-skill sync) ---"
    for b in "${broken_links[@]}"; do
      local name agent path target
      name=$(echo "$b" | jq -r '.name')
      agent=$(echo "$b" | jq -r '.agent')
      path=$(echo "$b" | jq -r '.path')
      target=$(echo "$b" | jq -r '.target')
      printf "  %-20s agent=%-10s -> %s (missing)\n" "$name" "$agent" "$target"
    done
    echo
  fi

  # Orphans
  if [[ ${#orphans[@]} -gt 0 ]]; then
    echo "--- Orphan Directories in ~/.meta-skill/skills/ (import with: meta-skill import <name>) ---"
    for o in "${orphans[@]}"; do
      local name path
      name=$(echo "$o" | jq -r '.name')
      path=$(echo "$o" | jq -r '.path')
      printf "  %-25s %s\n" "$name" "$path"
    done
    echo
  fi

  if [[ $total_unmanaged -gt 0 ]]; then
    info "Run 'meta-skill import <name>' to bring unmanaged skills under management."
  fi
  if [[ ${#orphans[@]} -gt 0 ]]; then
    info "Run 'meta-skill import <name> --orphan' to register orphan directories."
  fi
}

output_json() {
  local findings_json
  findings_json=$(printf '%s\n' "${findings[@]}" | jq -s '.')

  local orphans_json
  orphans_json=$(printf '%s\n' "${orphans[@]}" | jq -s '.')

  local broken_json
  broken_json=$(printf '%s\n' "${broken_links[@]}" | jq -s '.')

  local managed_count
  managed_count=$(echo "$findings_json" | jq '[.[] | select(.status == "managed")] | length')
  local unmanaged_symlink_count
  unmanaged_symlink_count=$(echo "$findings_json" | jq '[.[] | select(.status == "unmanaged-symlink")] | length')
  local unmanaged_dir_count
  unmanaged_dir_count=$(echo "$findings_json" | jq '[.[] | select(.status == "unmanaged-directory")] | length')
  local orphan_count=${#orphans[@]}
  local broken_count=${#broken_links[@]}
  local dup_count
  dup_count=$(echo "$findings_json" | jq '[.[] | select(.duplicate == true)] | length')

  jq -n \
    --argjson findings "$findings_json" \
    --argjson orphans "$orphans_json" \
    --argjson broken_links "$broken_json" \
    --arg scan_time "$(timestamp)" \
    --argjson summary "$(jq -n \
      --argjson managed "$managed_count" \
      --argjson unmanaged_symlink "$unmanaged_symlink_count" \
      --argjson unmanaged_directory "$unmanaged_dir_count" \
      --argjson orphans "$orphan_count" \
      --argjson broken "$broken_count" \
      --argjson duplicates "$dup_count" \
      '{managed: $managed, unmanaged_symlink: $unmanaged_symlink, unmanaged_directory: $unmanaged_directory, orphans: $orphans, broken: $broken, duplicates: $duplicates}')" \
    '{scan_time: $scan_time, findings: $findings, orphans: $orphans, broken_links: $broken_links, summary: $summary}'
}

# ---- helpers for counts ----

count_by_status() {
  local status="$1"
  local count=0
  for f in "${findings[@]}"; do
    [[ $(echo "$f" | jq -r '.status') == "$status" ]] && ((count++)) || true
  done
  echo "$count"
}

count_duplicates() {
  local count=0
  for f in "${findings[@]}"; do
    [[ $(echo "$f" | jq -r '.duplicate // false') == "true" ]] && ((count++)) || true
  done
  echo "$count"
}

# ---- main ----

main() {
  local target_agents=()
  local target_projects=()
  local output_json=false
  local include_projects=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --agent)
        target_agents+=("$2")
        shift 2
        ;;
      --project)
        target_projects+=("$2")
        shift 2
        ;;
      --json)
        output_json=true
        shift
        ;;
      --include-projects)
        include_projects=true
        shift
        ;;
      *)
        shift
        ;;
    esac
  done

  local manifest_data
  manifest_data=$(read_manifest)
  local registry_data
  registry_data=$(read_registry)

  findings=()
  orphans=()
  broken_links=()

  # Determine which agents to scan
  local agents_to_scan=()
  if [[ ${#target_agents[@]} -gt 0 ]]; then
    agents_to_scan=("${target_agents[@]}")
  else
    # Scan all agents whose home directory exists
    local all_agents
    all_agents=$(echo "$registry_data" | jq -r '.agents | keys[]')
    while IFS= read -r agent; do
      if [[ -n "$agent" ]]; then
        local home_dir
        home_dir=$(expand_path "$(echo "$registry_data" | jq -r ".agents[\"$agent\"].home // empty")")
        if [[ -d "$home_dir" ]]; then
          agents_to_scan+=("$agent")
        fi
      fi
    done <<< "$all_agents"
  fi

  # Scan agent global skill dirs
  for agent in "${agents_to_scan[@]}"; do
    local agent_skill_dir
    agent_skill_dir=$(expand_path "$(echo "$registry_data" | jq -r ".agents[\"$agent\"].skill_dir // empty")")
    scan_agent_dir "$agent" "$agent_skill_dir" ""
  done

  # Scan project skill dirs if requested
  if [[ ${#target_projects[@]} -gt 0 ]]; then
    for project in "${target_projects[@]}"; do
      if [[ ! -d "$project" ]]; then
        warn "Project directory not found: $project"
        continue
      fi
      for agent in "${agents_to_scan[@]}"; do
        local project_skill_dir_rel
        project_skill_dir_rel=$(echo "$registry_data" | jq -r ".agents[\"$agent\"].project_skill_dir // empty")
        if [[ -n "$project_skill_dir_rel" ]]; then
          local full_path="${project}/${project_skill_dir_rel#./}"
          scan_agent_dir "$agent" "$full_path" "$project"
        fi
      done
    done
  fi

  # Auto-discover projects if --include-projects
  if $include_projects; then
    info "Scanning projects with known agent config dirs..."
    local search_dirs=("$HOME/dev" "$HOME/projects" "$HOME/develop" "$HOME/src" "$HOME/code" "$HOME/git")
    for search_dir in "${search_dirs[@]}"; do
      [[ ! -d "$search_dir" ]] && continue
      while IFS= read -r -d '' config_dir; do
        local project_dir
        project_dir=$(dirname "$(dirname "$config_dir")")
        for agent in "${agents_to_scan[@]}"; do
          local project_skill_dir_rel
          project_skill_dir_rel=$(echo "$registry_data" | jq -r ".agents[\"$agent\"].project_skill_dir // empty")
          if [[ -n "$project_skill_dir_rel" ]]; then
            local skill_dir="${project_dir}/${project_skill_dir_rel#./}"
            scan_agent_dir "$agent" "$skill_dir" "$project_dir"
          fi
        done
      done < <(find "${search_dir}" -maxdepth 3 -type d -name "skills" -path "*/.trae-cn/skills" -print0 2>/dev/null || true)
    done
  fi

  # Scan orphans and broken links
  scan_orphans
  scan_broken_links
  detect_duplicates

  # Output
  if $output_json; then
    output_json
  else
    output_table
  fi
}

main "$@"
