#!/usr/bin/env bash
# meta-skill — Universal skill manager (dispatcher)
# Usage: meta-skill <command> [options]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Resolve symlinks: if meta-skill is symlinked from ~/.meta-skill/bin/,
# the operation scripts live in ~/.meta-skill/scripts/
RESOLVED_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")"
SCRIPTS_DIR="${RESOLVED_DIR}/scripts"
# Fallback: if scripts/ is not in the resolved dir, try parent of script dir
if [[ ! -d "${SCRIPTS_DIR}" ]]; then
  SCRIPTS_DIR="$(dirname "${SCRIPT_DIR}")/scripts"
fi
if [[ ! -d "${SCRIPTS_DIR}" ]]; then
  SCRIPTS_DIR="${SCRIPT_DIR}/scripts"
fi

usage() {
  echo "meta-skill - Universal skill manager"
  echo
  echo "Usage: meta-skill <command> [options]"
  echo
  echo "Commands:"
  echo "  scan      [--agent <a>] [--project <p>] [--json] [--include-projects]"
  echo "  import    <name> [--source <url>] [--agent <a>] [--project <p>] [--all] [--orphan] [--dry-run]"
  echo "  install   <name> --source <url> [--all] [--agent <a>] [--project <p>]"
  echo "  update    <name> [--all]"
  echo "  uninstall <name> [--agent <a>] [--project <p>]"
  echo "  list      [--agent <a>] [--project <p>] [--detail]"
  echo "  sync"
  echo "  info      <name>"
  exit 0
}

main() {
  if [[ $# -eq 0 ]]; then
    usage
  fi

  local cmd="$1"
  shift

  local script=""

  case "$cmd" in
    scan)      script="${SCRIPTS_DIR}/scan-skills.sh" ;;
    import)    script="${SCRIPTS_DIR}/import-skill.sh" ;;
    install)   script="${SCRIPTS_DIR}/install-skill.sh" ;;
    update)    script="${SCRIPTS_DIR}/update-skill.sh" ;;
    uninstall) script="${SCRIPTS_DIR}/uninstall-skill.sh" ;;
    list|ls)   script="${SCRIPTS_DIR}/list-skills.sh" ;;
    sync)      script="${SCRIPTS_DIR}/sync-skills.sh" ;;
    info)      script="${SCRIPTS_DIR}/info-skill.sh" ;;
    *) echo "ERROR: Unknown command: $cmd. Try 'meta-skill' for help." >&2; exit 1 ;;
  esac

  if [[ ! -f "$script" ]]; then
    echo "ERROR: Script not found: $script" >&2
    echo "Run 'meta-skill installer' to redeploy." >&2
    exit 1
  fi

  exec "$script" "$@"
}

main "$@"
