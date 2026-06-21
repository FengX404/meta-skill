#!/usr/bin/env bash
# sync-skills.sh — Sync/repair all symlinks across agents and projects
# Usage: sync-skills.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

main() {
  info "Syncing all symlinks..."

  local manifest_data
  manifest_data=$(read_manifest)
  local registry_data
  registry_data=$(read_registry)

  local fixed=0

  local names
  names=$(echo "$manifest_data" | jq -r '.skills | keys[]')
  for name in $names; do
    local dest="${SKILLS_DIR}/${name}"

    if [[ ! -d "$dest" ]]; then
      warn "Skill directory missing: $dest. Remove from manifest with: meta-skill uninstall $name"
      continue
    fi

    local entry
    entry=$(read_skill_manifest "$name")

    # Sync agent links
    local agents_json
    agents_json=$(echo "$entry" | jq -r '.agents[]')
    while IFS= read -r agent; do
      if [[ -n "$agent" ]]; then
        local agent_dir
        agent_dir=$(expand_path "$(echo "$registry_data" | jq -r ".agents[\"$agent\"].skill_dir // empty")")
        if [[ -n "$agent_dir" ]]; then
          mkdir -p "$agent_dir"
          local link_path="${agent_dir}/${name}"
          if [[ ! -e "$link_path" ]]; then
            ln -s "$dest" "$link_path"
            info "Fixed agent link: $link_path -> $dest"
            ((fixed++)) || true
          elif [[ -L "$link_path" ]] && [[ "$(readlink "$link_path")" != "$dest" ]]; then
            rm "$link_path"
            ln -s "$dest" "$link_path"
            info "Fixed agent link (wrong target): $link_path -> $dest"
            ((fixed++)) || true
          fi
        fi
      fi
    done <<< "$agents_json"

    # Sync project links
    local projects_json
    projects_json=$(echo "$entry" | jq -r '.projects | keys[]')
    while IFS= read -r project; do
      if [[ -n "$project" ]] && [[ -d "$project" ]]; then
        local pa
        pa=$(echo "$entry" | jq -r ".projects[\"$project\"][]")
        while IFS= read -r agent; do
          if [[ -n "$agent" ]]; then
            local skill_dir_rel
            skill_dir_rel=$(echo "$registry_data" | jq -r ".agents[\"$agent\"].skill_dir // empty")
            if [[ -z "$skill_dir_rel" ]]; then continue; fi
            local rel="${skill_dir_rel#\~/}"
            local project_skill_dir="${project}/${rel}"
            mkdir -p "$project_skill_dir"
            local link_path="${project_skill_dir}/${name}"
            if [[ ! -e "$link_path" ]]; then
              ln -s "$dest" "$link_path"
              info "Fixed project link: $link_path"
              ((fixed++)) || true
            fi
          fi
        done <<< "$pa"
      fi
    done <<< "$projects_json"
  done

  if [[ $fixed -eq 0 ]]; then
    info "All links are intact. Nothing to fix."
  else
    info "Fixed $fixed link(s)."
  fi
}

main "$@"
