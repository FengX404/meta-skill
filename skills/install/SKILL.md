---
name: "meta-skill:install"
description: "Install a skill from a source to ~/.meta-skill/skills/ and link to target agents/projects. Invoke when user asks to install or add a skill. Runs meta-skill CLI deterministically."
---

# Install Skill

Execute `~/.meta-skill/scripts/install-skill.sh` (or `meta-skill install`). All steps are deterministic — you do NOT manually manipulate files.

## Workflow

Collect all required information before executing. The skill is always stored centrally at `~/.meta-skill/skills/<name>/`, but must be linked to an agent or project to be usable.

**1. Skill name** — usually clear from user's request (e.g., "install code-reviewer").

**2. Source (`--source`)** — required for installation.

- If user provided a URL or local path → use it directly.
- If user did NOT provide a source → ask: *"Which source? (GitHub URL, SkillHub URL, or local directory path)"*

**3. Target** — where to link the skill.

- If user specified a target (e.g., "for TRAE", "into project Y", "for all agents") → use `--agent` / `--project` / `--all`.
- If user did NOT specify a target → ask: *"Where should this skill be linked? Available agents: cursor, trae, claude-code, windsurf, ... Or a project path?"*

Only when all three pieces are collected, assemble and execute the command.

## Command

```bash
~/.meta-skill/scripts/install-skill.sh <skill-name> --source <url|path> [--all] [--agent <name>] [--project <path>]
```

## Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `<skill-name>` | Yes | Unique skill identifier (e.g., `code-reviewer`) |
| `--source` | Yes | GitHub URL, SkillHub URL, or local directory path |
| `--all` | No | Link skill to all agents whose home directory exists |
| `--agent` | No | Link to a specific agent. Repeatable. |
| `--project` | No | Link into a project directory. Repeatable. |

## Examples

```bash
# Install from GitHub, link to all installed agents
~/.meta-skill/scripts/install-skill.sh code-reviewer --source https://github.com/user/skills --all

# Install from local dir, link only to TRAE
~/.meta-skill/scripts/install-skill.sh my-debugger --source /path/to/skill --agent trae

# Install and link to a project
~/.meta-skill/scripts/install-skill.sh pdf-tools --source https://github.com/skillhub/pdf --project ~/my-project
```

## Error Handling

- If the CLI exits non-zero, read its stderr for the error message and report it to the user.
- If skill already exists: CLI will error. Ask user if they want to re-install (uninstall first).
- If source is unreachable: CLI will error with "Failed to clone". Suggest checking the URL.
- If agent or project is unknown: CLI will warn and skip. The main install still succeeds.

## What the CLI Does (for reference)

1. git clone (or cp for local) the skill into `~/.meta-skill/skills/<name>/`
2. Register in `~/.meta-skill/manifests/<name>.json` with source info + timestamps (and add to `manifest.json` index)
3. Create symlinks: `<agent-skill-dir>/<name>` → `~/.meta-skill/skills/<name>/`
4. With `--project`: also create symlinks in `<project>/<agent-config>/skills/<name>/`
5. Update per-skill manifest with agent/project linkage
