#!/usr/bin/env bash
# info-skill.sh — Show detailed info about a managed skill
# Usage: info-skill.sh <name>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

main() {
  local skill_name="$1"
  [[ -z "$skill_name" ]] && die "skill name required"

  local entry
  entry=$(read_skill_manifest "$skill_name")
  if [[ -z "$entry" ]]; then
    die "Skill '$skill_name' not found in manifest"
  fi

  echo "=== $skill_name ==="
  echo
  echo "Source:"
  echo "$entry" | jq '.source'
  echo
  local subpath
  subpath=$(echo "$entry" | jq -r '.source.subpath // empty')
  if [[ -n "$subpath" ]]; then
    echo "Subpath within repo: $subpath"
    echo
  fi
  echo "Timeline:"
  echo "$entry" | jq '{installed_at, updated_at}'
  echo
  echo "Installed in agents:"
  echo "$entry" | jq '.agents'
  echo
  echo "Installed in projects:"
  echo "$entry" | jq '.projects'
  echo
  echo "Skill directory: ${SKILLS_DIR}/${skill_name}"

  if [[ -d "${SKILLS_DIR}/${skill_name}" ]]; then
    echo "  Size: $(du -sh "${SKILLS_DIR}/${skill_name}" 2>/dev/null | cut -f1)"
    if [[ -d "${SKILLS_DIR}/${skill_name}/.git" ]]; then
      echo "  Git remote: $(cd "${SKILLS_DIR}/${skill_name}" && git remote get-url origin 2>/dev/null || echo 'unknown')"
      echo "  Git HEAD: $(cd "${SKILLS_DIR}/${skill_name}" && git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
    fi
  else
    warn "Skill directory is missing!"
  fi
}

main "$@"
