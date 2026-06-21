---
name: "meta-skill:scan"
description: "Scan all agents and projects to discover existing skills. Read-only, safe to run anytime. Invoke when user wants to find, discover, or audit skills before import."
---

# Scan Skills

Execute `~/.meta-skill/scripts/scan-skills.sh` (or `meta-skill scan`). This is a **read-only** operation — it never modifies any files or links.

## Purpose

Discover all skills that exist across the user's environment, regardless of whether they are managed by meta-skill. This is the essential first step before importing skills into management.

## Workflow

No confirmation needed — scanning is always safe. Just run the command with appropriate filters.

**If user asks "what skills do I have?" or "scan my skills"**:
→ Run `meta-skill scan` without filters.

**If user wants to see only specific agents or projects**:
→ Add `--agent` or `--project` flags to scope the scan.

**If user wants machine-readable output for scripting**:
→ Add `--json`.

## Command

```bash
~/.meta-skill/scripts/scan-skills.sh [--agent <name>] [--project <path>] [--json] [--include-projects]
```

## Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| (none) | No | Scan all agents that have an existing home directory |
| `--agent <name>` | No | Scan only a specific agent. Repeatable. |
| `--project <path>` | No | Also scan a specific project directory. Repeatable. |
| `--include-projects` | No | Auto-discover projects in ~/dev, ~/projects, ~/develop, ~/src, ~/code, ~/git |
| `--json` | No | Output as JSON (for scripting / piping) |

## Examples

```bash
# Full scan of all installed agents
meta-skill scan

# Scan only specific agents
meta-skill scan --agent trae --agent cursor

# Scan agents + a specific project
meta-skill scan --project ~/my-project

# Auto-discover projects and output JSON
meta-skill scan --include-projects --json
```

## Output

### Table mode (default)

The CLI outputs a categorized report:

```
[meta-skill] Skill Scan Report

Summary:
  Managed (via meta-skill): 3
  Unmanaged symlinks:       4
  Unmanaged directories:    2
  Broken symlinks:          1
  Orphan dirs in repo:      1
  Potential duplicates:     2

--- Managed (by meta-skill) ---
  NAME                      TYPE     AGENT      PATH
  code-reviewer             agent    trae       /Users/.../.trae-cn/skills/code-reviewer
  pdf-tools                 agent    cursor     /Users/.../.cursor/skills/pdf-tools

--- Unmanaged (candidates for import) ---
  NAME                      TYPE      AGENT      KIND     TARGET
  my-debugger               agent     trae       symlink  /Users/.../dev/skills/my-debugger
  daily-report              agent     cursor     symlink  /Users/.../dev/skills/daily-report [DUP]
  daily-report              agent     trae       symlink  /Users/.../dev/skills/daily-report [DUP]
  local-helper              agent     trae       directory (local directory)

--- Broken Symlinks (fix with: meta-skill sync) ---
  old-skill                 agent=trae       -> /nonexistent/path (missing)

--- Orphan Directories in ~/.meta-skill/skills/ (import with: meta-skill import <name>) ---
  forgotten-skill           /Users/.../.meta-skill/skills/forgotten-skill

[meta-skill] Run 'meta-skill import <name>' to bring unmanaged skills under management.
[meta-skill] Run 'meta-skill import <name> --orphan' to register orphan directories.
```

### JSON mode (`--json`)

```json
{
  "scan_time": "2026-06-21T10:30:00Z",
  "findings": [
    {
      "name": "my-debugger",
      "location_type": "agent",
      "agent": "trae",
      "project": "",
      "path": "/Users/.../.trae-cn/skills/my-debugger",
      "kind": "symlink",
      "status": "unmanaged-symlink",
      "target": "/Users/.../dev/skills/my-debugger",
      "duplicate": false
    }
  ],
  "orphans": [
    {"name": "forgotten-skill", "path": "/Users/.../.meta-skill/skills/forgotten-skill"}
  ],
  "broken_links": [
    {"name": "old-skill", "agent": "trae", "path": "...", "target": "/nonexistent"}
  ],
  "summary": {
    "managed": 3,
    "unmanaged_symlink": 4,
    "unmanaged_directory": 2,
    "orphans": 1,
    "broken": 1,
    "duplicates": 2
  }
}
```

## Classification Logic

| Filesystem state | Classification | Import strategy |
|-----------------|----------------|-----------------|
| Symlink → `~/.meta-skill/skills/*` | `managed` | Already managed, no action needed |
| Symlink → other path | `unmanaged-symlink` | Copy/clone source to `~/.meta-skill/skills/`, update manifest |
| Real directory (not symlink) | `unmanaged-directory` | Move to `~/.meta-skill/skills/`, create symlinks, source=`local` |
| Broken symlink | `broken-symlink` | Fix with `meta-skill sync` or remove |

## Duplicate Detection

Two or more entries pointing to the same symlink target are flagged as `[DUP]`. During import, the user can choose which instance to keep (or merge them).

## Error Handling

- Scan is read-only — no destructive operations. Safe to run repeatedly.
- If an agent's home directory doesn't exist, it is silently skipped.
- If a project directory doesn't exist, a warning is shown and scanning continues.
- If jq is not installed, the script will error. The SKILL.md that invokes scan should ensure jq is present on the system.

## Next Steps After Scan

1. Review the "Unmanaged" section — these are candidates for `meta-skill import`
2. Check `[DUP]` entries — decide which copies to import
3. Fix broken links with `meta-skill sync`
4. Register orphans with `meta-skill import <name> --orphan`
