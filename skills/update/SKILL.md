---
name: "meta-skill:update"
description: "Update a skill from its source and sync changes to linked agents/projects. Invoke when user asks to update or refresh a skill. Runs meta-skill CLI deterministically."
---

# Update Skill

Execute `~/.meta-skill/scripts/update-skill.sh` (or `meta-skill update`). All steps are deterministic — you do NOT manually run git or edit files.

## Workflow

Collect all required information before executing.

**1. Determine scope** — which skill(s) to update.

- If user specified a skill name (e.g., "update code-reviewer") → use that name.
- If user said "update all" or "update everything" → use `--all`.
- If user did NOT specify (just "update my skills") → ask: *"Update which skill? Or use --all to update everything?"*

**2. Confirm** — no additional information needed. Run the command with the collected parameters.

## Command

```bash
~/.meta-skill/scripts/update-skill.sh <skill-name>
~/.meta-skill/scripts/update-skill.sh --all
```

## Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `<skill-name>` | Yes (or `--all`) | Name of the skill to update |
| `--all` | No | Update all managed skills in sequence |

## Examples

```bash
# Update a single skill
~/.meta-skill/scripts/update-skill.sh code-reviewer

# Update all skills
~/.meta-skill/scripts/update-skill.sh --all
```

## Error Handling

- If skill not found in manifest: CLI returns error. Suggest `meta-skill list` to see installed skills.
- If git pull fails (network issue, repo gone): CLI returns error. Show the stderr to user.
- If local source no longer exists: CLI warns and skips. Suggest re-installing with a new source.
- No changes: CLI reports "No changes detected" (exit 0).

## Update Behavior by Source Type

- **GitHub / SkillHub**: `git fetch origin && git pull origin HEAD`. Updates version to new `git rev-parse HEAD`.
- **Local**: `diff -rq` compares source and destination. If different, re-copies. If identical, no-op.

Since symlinks point to the central `~/.meta-skill/skills/<name>/` directory, updating the central copy automatically updates all linked agents and projects. No additional sync needed.

## What the CLI Does (for reference)

1. Reads skill source info from `~/.meta-skill/manifest.json`
2. git pull (or diff + re-copy for local) to get latest
3. Updates `source.version` and `updated_at` in manifest
4. Symlinks follow automatically — no extra work needed
