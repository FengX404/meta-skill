---
name: "meta-skill:list"
description: "List all managed skills, their sources, and distribution across agents/projects. Invoke when user asks to show, view, or list skills. Runs meta-skill CLI deterministically."
---

# List Skills

Execute `~/.meta-skill/scripts/list-skills.sh` (or `meta-skill list`). The CLI reads the manifest index and per-skill files, then formats output — you do NOT manually query.

## Command

```bash
~/.meta-skill/scripts/list-skills.sh [--agent <name>] [--project <path>] [--detail]
```

## Parameters

| Parameter | Description |
|-----------|-------------|
| (none) | Show summary table of all skills |
| `--agent <name>` | Filter: show only skills linked to this agent |
| `--project <path>` | Filter: show only skills linked to this project |
| `--detail` | Show full details for each skill (source, timestamps, full agent list) |

## Examples

```bash
# Show all skills summary
meta-skill list

# Show skills installed for TRAE
meta-skill list --agent trae

# Show skills in a specific project
meta-skill list --project ~/my-project

# Show detailed info
meta-skill list --detail
```

## Output

The CLI outputs a formatted summary table and runs an integrity check automatically:

```
[meta-skill] Skills managed: 5

NAME                 SOURCE       VERSION      AGENTS                    PROJECTS
----------------------------------------------------------------------------------------------------
meta-skill           github       1.0.0        trae, cursor              -
code-reviewer        github       a1b2c3d      trae, claude-code         ~/proj1
pdf-tools            skillhub     d4e5f6g      trae                      -
```

Integrity check detects:
- Orphan skill directories (on disk but not in manifest)
- Broken symlinks in agent directories
- Skills in manifest with missing directories

If issues are found, the CLI reports them and suggests `meta-skill sync` to fix.

## Additional Commands

```bash
# Show detailed info about a specific skill
meta-skill info <skill-name>

# Repair broken symlinks
meta-skill sync
```
