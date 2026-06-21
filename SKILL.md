---
name: "meta-skill"
description: "Universal skill manager for AI coding agents (Claude Code, Cursor, TRAE, opencode, etc.). Invoke when user wants to install, update, uninstall, list, or sync skills across agents and projects."
---

# Meta-Skill

A universal skill manager that maintains a central `~/.meta-skill/` repository and manages skill distribution across multiple AI coding agents and projects.

## Architecture

```
~/.meta-skill/           # Global skill repository (created by install script)
├── metadata.json        # Meta-skill metadata (GitHub repo, version)
├── manifest.json        # Skill/Agent/Project registry
└── skills/              # All managed skills (organized by name)
```

## Key Concepts

- **Skill**: A reusable capability package. Each skill has a source (GitHub, SkillHub, local directory) and can only be updated from its source.
- **Agent**: An AI coding tool (Claude Code, Cursor, TRAE, etc.) that consumes skills from its own skill directory.
- **Project**: A local project directory that may have agent-specific skill configurations.
- **Source**: The origin of a skill — determines how updates are fetched.

## Lifecycle

```
scan → import → install → list → update → uninstall → sync
 ⬊                                                        ⬎
                  持续管理循环
```

- **Discovery phase** (once): `scan` → `import` — discover existing skills and bring them under management.
- **Management phase** (ongoing): `install` / `update` / `uninstall` / `list` / `sync` — operate on managed skills.

## Sub-Skills

| Sub-Skill | Trigger |
|-----------|---------|
| `scan` | Discover all skills across agents, projects, and the meta-skill repository (read-only) |
| `import` | Bring an existing unmanaged skill into meta-skill management |
| `install` | Install a new skill from a source to `~/.meta-skill/skills/` and link to target agents/projects |
| `update` | Update a skill from its source to `~/.meta-skill/skills/` and sync to installed agents |
| `uninstall` | Remove a skill from `~/.meta-skill/skills/` and unlink from agents/projects |
| `list` | List all managed skills, their sources, and distribution across agents/projects |

## Management CLI

The `meta-skill` command (symlinked to `~/.meta-skill/bin/meta-skill`) provides:

```
meta-skill scan [--agent <name>] [--project <path>] [--json] [--include-projects]
meta-skill import <skill-name> [--source <url>] [--agent <name>] [--project <path>] [--all] [--orphan] [--dry-run]
meta-skill install <skill-name> --source <url> [--agent <name>] [--project <path>]
meta-skill update <skill-name> [--all]
meta-skill uninstall <skill-name> [--agent <name>] [--project <path>]
meta-skill list [--agent <name>] [--project <path>] [--detail]
meta-skill sync
meta-skill info <skill-name>
```

## Installation Flags

```
./install.sh                        # Default: link only to agents with existing home dirs
./install.sh --all                  # Link to all 22 agents regardless
./install.sh --ide cursor,trae      # Link only to specified agents (comma-separated)
./install.sh --github <repo-url>    # Override GitHub repository URL
```

## Supported Agents

22 mainstream AI coding agents across 4 categories:

| Category | Agents |
|----------|--------|
| **IDE** | Cursor, Windsurf, TRAE, Kiro (Amazon), Antigravity (Google), Qoder, CodeBuddy, Zed AI |
| **CLI** | Claude Code, OpenCode, Codex CLI, Aider, Gemini CLI |
| **VS Code Ext** | Cline, RooCode, Continue.dev, Augment Code, Cody, Tabnine, GitHub Copilot |
| **IDE Ext** | JetBrains AI Assistant, Baidu Comate |

## Working with the Manifest

**Always use the CLI for mutations.** The `meta-skill` command is a deterministic bash script — it handles all edge cases correctly. Never manually edit `manifest.json` or files directly.

When the user asks to manage skills:
1. Identify which sub-skill matches the user's intent (scan / import / install / update / uninstall / list)
2. Load the corresponding sub-skill SKILL.md for exact CLI syntax
3. Run the `meta-skill` CLI command shown in the sub-skill
4. Report the CLI output to the user

For first-time users or "clean up my skills" requests: start with `scan` to discover what exists, then `import` to bring them under management.

If the CLI is not found, run `./install.sh` from the meta-skill project to redeploy it.
