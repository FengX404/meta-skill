# Contributing to Meta-Skill

Thanks for your interest in contributing! Here's how to get started.

## Development Setup

```bash
git clone https://github.com/FengX404/meta-skill.git
cd meta-skill
```

No build step required — meta-skill is pure bash. Just make sure you have `bash`, `git`, and `jq` installed.

## Making Changes

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-change`
3. Make your changes
4. Test by running `./install.sh` and exercising the changed commands
5. Commit with a clear message
6. Push and open a Pull Request

## Adding a New Agent

To add support for a new AI coding agent:

1. Add an entry to `templates/manifest.json` under `agents` with the following fields:
   - `name`: Display name
   - `home`: Agent's config home directory (e.g. `~/.agent`)
   - `skill_dir`: Global skill directory (e.g. `~/.agent/skills`)
   - `project_skill_dir`: Project-level skill directory (e.g. `./.agent/skills`)
   - `type`: One of `ide`, `cli`, `vscode-ext`, `ide-ext`
2. Test by running `./install.sh --ide <agent-key>`

## Code Style

- Bash scripts: follow existing conventions in the codebase
- Use `set -euo pipefail` in all scripts
- Use the shared library (`scripts/lib.sh`) for common operations
- Keep scripts focused — each script handles one command

## Reporting Issues

- Use GitHub Issues
- Include: OS, shell, `meta-skill` version, steps to reproduce, expected vs actual behavior

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
