#!/usr/bin/env bash
# update-skill.sh — Update a skill from its registered source
# Usage: update-skill.sh <name>
#        update-skill.sh --all

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

update_single() {
  local skill_name="$1"
  local entry
  entry=$(read_skill_manifest "$skill_name")
  if [[ -z "$entry" ]]; then
    warn "Skill '$skill_name' not found in manifest"
    return 1
  fi

  local source_type source_url dest version subpath
  source_type=$(echo "$entry" | jq -r '.source.type')
  source_url=$(echo "$entry" | jq -r '.source.url')
  subpath=$(echo "$entry" | jq -r '.source.subpath // empty')
  dest="${SKILLS_DIR}/${skill_name}"

  # For subpath skills, the real git repo is at _repo_<name>/
  local repo_dest="$dest"
  if [[ -n "$subpath" ]]; then
    repo_dest="${SKILLS_DIR}/_repo_${skill_name}"
    info "Updating skill: $skill_name (source: $source_type, subpath: $subpath)"
  else
    info "Updating skill: $skill_name (source: $source_type)"
  fi

  case "$source_type" in
    github|skillhub)
      if [[ -d "${repo_dest}/.git" ]]; then
        cd "$repo_dest"
        git_with_timeout fetch origin || { warn "Failed to fetch from origin"; return 1; }
        git merge FETCH_HEAD || { warn "Failed to merge updates"; return 1; }
        version=$(git rev-parse HEAD)
        info "Updated to $version"
      elif [[ -n "$subpath" ]]; then
        # Subpath skill with missing repo: re-clone the whole repo
        warn "Repository directory missing, re-cloning..."
        local tmp_clone="${repo_dest}.tmp.$$"
        if ! git_with_timeout clone "$source_url" "$tmp_clone"; then
          rm -rf "$tmp_clone"
          warn "Failed to clone"
          return 1
        fi
        rm -rf "$repo_dest"
        mv "$tmp_clone" "$repo_dest"
        version=$(cd "$repo_dest" && git rev-parse HEAD)
        # Re-create symlink if needed
        if [[ ! -L "$dest" ]] || [[ "$(readlink "$dest")" != "${repo_dest}/${subpath}" ]]; then
          rm -f "$dest"
          ln -s "${repo_dest}/${subpath}" "$dest"
          info "Re-created symlink: $dest → ${repo_dest}/${subpath}"
        fi
      else
        warn "Not a git repository, re-cloning..."
        local tmp_clone="${dest}.tmp.$$"
        if ! git_with_timeout clone "$source_url" "$tmp_clone"; then
          rm -rf "$tmp_clone"
          warn "Failed to clone"
          return 1
        fi
        rm -rf "$dest"
        mv "$tmp_clone" "$dest"
        version=$(cd "$dest" && git rev-parse HEAD)
      fi
      ;;
    local)
      if [[ -n "$subpath" ]]; then
        warn "Local source with subpath cannot be updated. Skipping."
        return 0
      fi
      if [[ -d "$source_url" ]]; then
        info "Comparing local source..."
        if diff -rq "$source_url" "$dest" > /dev/null 2>&1; then
          info "No changes detected"
        else
          warn "Local source differs. Re-copy..."
          local tmp_copy="${dest}.tmp.$$"
          cp -r "$source_url" "$tmp_copy"
          rm -rf "$dest"
          mv "$tmp_copy" "$dest"
          info "Local copy updated"
        fi
      else
        warn "Local source directory not found: $source_url. Update skipped."
        return 1
      fi
      version="local-$(timestamp)"
      ;;
  esac

  # Update manifest timestamps and version
  read_skill_manifest "$skill_name" | jq --arg version "$version" --arg updated_at "$(timestamp)" \
    '.source.version = $version | .updated_at = $updated_at' | write_skill_manifest "$skill_name"
  info "Manifest updated for '$skill_name'"
}

main() {
  local skill_name=""
  local update_all=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --all) update_all=true; shift ;;
      *) skill_name="$1"; shift ;;
    esac
  done

  if $update_all; then
    info "Updating all skills..."
    local names succeeded=0 failed=0
    names=$(read_manifest | jq -r '.skills | keys[]')
    for name in $names; do
      if update_single "$name"; then
        ((succeeded++)) || true
      else
        ((failed++)) || true
      fi
    done
    info "Update complete: $succeeded succeeded, $failed failed"
    return
  fi

  [[ -z "$skill_name" ]] && die "skill name required or --all"
  update_single "$skill_name"
}

main "$@"
