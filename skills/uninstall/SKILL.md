---
name: "meta-skill:uninstall"
description: "Uninstall a skill from ~/.meta-skill/skills/ and remove all links from agents/projects. Invoke when user asks to remove or uninstall a skill. Runs meta-skill CLI deterministically."
---

# Uninstall Skill

Execute `~/.meta-skill/scripts/uninstall-skill.sh` (or `meta-skill uninstall`). All steps are deterministic — you do NOT manually remove files.

## Workflow

Before executing, clarify the scope of removal.

**If the user already specified a scope** (e.g., "remove X from TRAE", "unlink X from project Y"):
→ Use `--agent` / `--project` to selectively remove links only.

**If the user did NOT specify a scope** (just "uninstall X"):
→ This triggers a **full uninstall** — deleting the skill directory and all agent/project links. Confirm with the user before proceeding:
*"This will remove all links and delete the skill. Confirm full uninstall, or specify a particular agent/project to unlink only?"*

## Command

```bash
~/.meta-skill/scripts/uninstall-skill.sh <skill-name> [--agent <name>] [--project <path>]
```

## Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `<skill-name>` | Yes | Name of the skill to uninstall |
| `--agent` | No | Remove only from a specific agent (keep skill and other links) |
| `--project` | No | Remove only from a specific project (keep skill and other links) |

## Examples

```bash
# Full uninstall (removes everything)
~/.meta-skill/scripts/uninstall-skill.sh code-reviewer

# Remove only from TRAE (skill stays installed for other agents)
~/.meta-skill/scripts/uninstall-skill.sh code-reviewer --agent trae

# Remove only from a project
~/.meta-skill/scripts/uninstall-skill.sh code-reviewer --project ~/my-project
```

## Error Handling

- If skill not found in manifest: CLI returns error. Suggest `meta-skill list` to check.
- If symlink is not managed by meta-skill (not a symlink, or wrong target): CLI warns and skips it safely.
- Selective uninstall (--agent/--project): CLI only removes that specific link, skill directory and other links remain intact.

## What the CLI Does (for reference)

**Full uninstall:**
1. Reads `manifests/<name>.json` to find all links
2. Shows summary: N agent links + M project links will be removed
3. Removes symlinks from all linked agents
4. Removes symlinks from all linked projects
5. Deletes `~/.meta-skill/skills/<name>/` directory
6. Removes `manifests/<name>.json` and deletes from `manifest.json` index

**Selective uninstall** (--agent or --project):
1. Removes only the specified symlink(s)
2. Updates per-skill manifest to reflect the removed link
3. Skill directory and other links remain untouched
