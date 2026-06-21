---
name: "meta-skill:import"
description: "Import an existing (unmanaged) skill into meta-skill management. Invoke after 'scan' when user wants to bring discovered skills under management."
---

# Import Skill

Execute `~/.meta-skill/scripts/import-skill.sh` (or `meta-skill import`). This brings an existing skill that was discovered by `meta-skill scan` into the managed system.

**Prerequisite:** Run `meta-skill scan` first to discover unmanaged skills.

## Workflow

Collect all required information before executing.

**1. Skill name** — from `meta-skill scan` output.

**2. Source (`--source`)** — optional.

- **If auto-detected**: The CLI will discover the skill's source from its symlink target or directory location.
- **If auto-detection fails** (e.g., target unreachable): Ask user: *"The source directory is unreachable. Provide a new source URL, or skip?"*

**3. Scope** — where to link after import.

- **If user specified agents** (e.g., "import my-debugger for trae and cursor") → use `--agent`.
- **If user said "import to all agents"** → use `--all`.
- **If user specified projects** → use `--project`.
- **If user did NOT specify**: Default behavior links only to the agent where the skill was found.

**4. Special case — orphan** (skill directory exists in `~/.meta-skill/skills/` but not in manifest):

- Use `--orphan` flag. No agent search is performed.

## Command

```bash
~/.meta-skill/scripts/import-skill.sh <skill-name> [--source <url>] [--agent <name>] [--project <path>] [--all] [--orphan] [--dry-run]
```

## Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `<skill-name>` | Yes | Name of the skill to import |
| `--source <url>` | No | Override auto-detected source URL |
| `--agent <name>` | No | Link to a specific agent after import. Repeatable. |
| `--project <path>` | No | Link into a project directory after import. Repeatable. |
| `--all` | No | Link to all agents with existing home directories |
| `--orphan` | No | Import an orphan directory from `~/.meta-skill/skills/` |
| `--dry-run` | No | Show what would happen without making changes |

## Examples

```bash
# Import an unmanaged skill (auto-detect source, link to the agent where found)
meta-skill import my-debugger

# Import and link to all agents
meta-skill import my-debugger --all

# Import to specific agents
meta-skill import my-debugger --agent trae --agent cursor

# Import with explicit source URL
meta-skill import my-debugger --source https://github.com/user/my-debugger --agent trae

# Import an orphan directory
meta-skill import forgotten-skill --orphan

# Dry run to preview
meta-skill import my-debugger --dry-run

# Import to a project
meta-skill import daily-report --project ~/my-project
```

## Import Strategies

The CLI auto-detects the skill's state and applies the appropriate strategy.

### Source Resolution

Source is determined with the following priority chain:

| Priority | Source | Example |
|----------|--------|---------|
| 1 | Explicit `--source` flag | `--source https://github.com/user/repo` |
| 2 | Skill's own metadata | `metadata.json` → `.source` / `.github`; `SKILL.md` frontmatter → `source:` / `github:`
| 3 | Git remote origin (normalized) | SSH → HTTPS: `git@github.com:user/repo.git` → `https://github.com/user/repo` |
| 4 | Local path fallback | `~/.meta-skill/skills/<name>/` (marked `local`) |

For skills inside a git repository **subdirectory**, the CLI walks up to find the git root, clones the entire repo, and records `source.subpath` in manifest. Example:

```
Target:  ~/dev/tools/skills/my-skill/     (subdirectory)
Git root: ~/dev/tools/                     (.git found by walking up)
Result:
  - Clones ~/dev/tools/ → ~/.meta-skill/skills/_repo_my-skill/
  - Symlinks ~/.meta-skill/skills/my-skill → _repo_my-skill/skills/my-skill/
  - Manifest: { source: { url: "https://github.com/user/tools", subpath: "skills/my-skill" } }
```

### Strategy 1: Unmanaged Symlink

Skill exists as a symlink pointing to a path **outside** `~/.meta-skill/skills/`.

**What happens:**
1. Source resolved via priority chain (git root walk, metadata, remote origin)
2. If subpath detected → clone entire repo, symlink subdirectory
3. If target is a git repo → `git clone` to `~/.meta-skill/skills/<name>/`
4. If target is a plain directory → `cp -R` to `~/.meta-skill/skills/<name>/`
5. Old symlink at the agent's skill dir is **removed**
6. New symlink is created pointing to the managed directory
7. Registered in manifest with resolved source

### Strategy 2: Unmanaged Directory

Skill exists as a real directory (not symlink) in an agent's skill dir.

**What happens:**
1. Source resolved via priority chain (checks if directory is inside a git repo)
2. If part of a git repo with remote → clone + symlink (preserves update capability)
3. Otherwise → directory is **moved** to `~/.meta-skill/skills/<name>/`
4. Symlink created in its place pointing to the managed directory
5. Registered in manifest with resolved source

### Strategy 3: Orphan

Directory exists in `~/.meta-skill/skills/<name>/` but is not registered in manifest.

**What happens:**
1. Directory stays in place (it's already in the right location)
2. Source resolved via priority chain (git remote, metadata)
3. Registered in manifest
4. Symlinks created in agent directories

## Post-Import Dedup Check

After importing, the CLI automatically scans for other instances of the same skill in other agents and warns if duplicates are found. The user can then run `meta-skill install <name> --agent <a>` to replace those with managed links.

## Error Handling

- **Skill already managed**: Error. Use `meta-skill update` or `meta-skill uninstall` instead.
- **Skill not found in any agent**: Error. Try `--orphan` if it's in `~/.meta-skill/skills/`. Otherwise run `meta-skill scan` first.
- **Destination already exists**: Error. Remove `~/.meta-skill/skills/<name>/` first if intentional.
- **Target unreachable (symlink broken)**: Error. Use `--source` to specify an alternative source URL.
- **Local copy in another agent**: Warning only. Import succeeds; the user decides what to do with the duplicate.

## Relationship with `install`

| Command | When to use |
|---------|-------------|
| `install` | Install a **new** skill from a known source (GitHub, SkillHub, local path) |
| `import` | Bring an **existing** skill already on disk into management |

After import, the skill behaves identically to an installed skill — `update`, `uninstall`, `list` all work the same.
