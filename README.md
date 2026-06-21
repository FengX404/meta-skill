# Meta-Skill

Universal skill manager for AI coding agents. Maintains a central `~/.meta-skill/` repository and manages skill distribution across multiple AI coding agents and projects.

## Why

AI coding agents (Cursor, Claude Code, TRAE, Windsurf, etc.) each have their own skill/prompt directories. When you use multiple agents, keeping skills in sync is manual and error-prone. Meta-skill solves this with a single source of truth.

## Quick Start

```bash
# Install (macOS / Linux)
curl -fsSL https://raw.githubusercontent.com/FengX404/meta-skill/main/install.sh | bash

# Or clone and install
git clone https://github.com/FengX404/meta-skill.git
cd meta-skill && ./install.sh

# Windows (PowerShell)
powershell -ExecutionPolicy Bypass -File install.ps1
```

After installation, the `meta-skill` CLI is available in your PATH.

## Usage

```bash
# Discover existing skills across all agents
meta-skill scan

# Import an unmanaged skill into meta-skill
meta-skill import <skill-name> --source <url>

# Install a skill from GitHub
meta-skill install <skill-name> --source https://github.com/user/skill-repo

# List all managed skills
meta-skill list

# Update a skill from its source
meta-skill update <skill-name>

# Uninstall a skill
meta-skill uninstall <skill-name>

# Sync all skills
meta-skill sync

# Show skill details
meta-skill info <skill-name>
```

## Installation Flags

```bash
./install.sh                        # Default: link only to agents with existing home dirs
./install.sh --all                  # Link to all 22 agents regardless
./install.sh --ide cursor,trae      # Link only to specified agents (comma-separated)
./install.sh --github <repo-url>    # Override GitHub repository URL
```

## Architecture

```
~/.meta-skill/           # Global skill repository
├── metadata.json        # Meta-skill metadata (GitHub repo, version)
├── manifest.json        # Skill/Agent/Project registry
├── bin/meta-skill       # CLI entry point
├── scripts/             # Operation scripts
├── skills/              # All managed skills (organized by name)
└── backups/             # Manifest backups
```

### Key Concepts

- **Skill**: A reusable capability package. Each skill has a source (GitHub, SkillHub, local directory) and can only be updated from its source.
- **Agent**: An AI coding tool (Claude Code, Cursor, TRAE, etc.) that consumes skills from its own skill directory.
- **Project**: A local project directory that may have agent-specific skill configurations.
- **Source**: The origin of a skill — determines how updates are fetched.

### Lifecycle

```
scan → import → install → list → update → uninstall → sync
 ⬊                                                        ⬎
                  continuous management loop
```

- **Discovery phase** (once): `scan` → `import` — discover existing skills and bring them under management.
- **Management phase** (ongoing): `install` / `update` / `uninstall` / `list` / `sync` — operate on managed skills.

## Supported Agents

22 mainstream AI coding agents across 4 categories:

| Category | Agents |
|----------|--------|
| **IDE** | Cursor, Windsurf, TRAE, Kiro (Amazon), Antigravity (Google), Qoder, CodeBuddy, Zed AI |
| **CLI** | Claude Code, OpenCode, Codex CLI, Aider, Gemini CLI |
| **VS Code Ext** | Cline, RooCode, Continue.dev, Augment Code, Cody, Tabnine, GitHub Copilot |
| **IDE Ext** | JetBrains AI Assistant, Baidu Comate |

## Project Structure

```
meta-skill/
├── SKILL.md              # Skill definition for meta-skill itself
├── meta-skill.sh         # CLI dispatcher
├── install.sh            # Installer (macOS / Linux)
├── install.ps1           # Installer (Windows)
├── scripts/              # Operation scripts
│   ├── lib.sh            # Shared library
│   ├── scan-skills.sh
│   ├── import-skill.sh
│   ├── install-skill.sh
│   ├── update-skill.sh
│   ├── uninstall-skill.sh
│   ├── list-skills.sh
│   ├── sync-skills.sh
│   └── info-skill.sh
├── skills/               # Sub-skill definitions
│   ├── scan/SKILL.md
│   ├── import/SKILL.md
│   ├── install/SKILL.md
│   ├── update/SKILL.md
│   ├── uninstall/SKILL.md
│   └── list/SKILL.md
└── templates/            # Template files for installation
    ├── manifest.json
    └── metadata.json
```

## Requirements

- **bash** 4.0+
- **git**
- **jq**

## License

[MIT](LICENSE)

## 关注作者

| 博客 | 小红书 | X | 公众号 |
|:---:|:---:|:---:|:---:|
| [![博客](./assets/blog-qr.png)](https://fengx404.com/blog/) | [![小红书](./assets/xiaohongshu-qr.png)](https://www.xiaohongshu.com/user/profile/5fa9ed6d000000000100a8be) | [![X](./assets/x-qr.png)](https://x.com/FengX404) | ![公众号](./assets/wechat-qr.jpg) |
| [fengx404.com/blog](https://fengx404.com/blog/) | [FengX](https://www.xiaohongshu.com/user/profile/5fa9ed6d000000000100a8be) | [@FengX404](https://x.com/FengX404) | FengX |
