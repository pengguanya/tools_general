# Neovim Maintenance Guide

A comprehensive guide to maintaining your Neovim installation across machines using AppImage, kickstart.nvim fork sync, and automated health checks.

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Daily Use Scenarios](#daily-use-scenarios)
4. [Setup on a New Machine](#setup-on-a-new-machine)
5. [Updating Neovim Binary](#updating-neovim-binary)
6. [Syncing with Upstream Kickstart.nvim](#syncing-with-upstream-kickstartnvim)
7. [Plugin & LSP Maintenance](#plugin--lsp-maintenance)
8. [Full Maintenance Routine](#full-maintenance-routine)
9. [Using with Claude Code](#using-with-claude-code)
10. [Portability to Other AI Agents](#portability-to-other-ai-agents)
11. [Troubleshooting](#troubleshooting)
12. [Reference](#reference)

---

## Overview

This system manages five concerns:

| Concern | Script | What it does |
|---------|--------|--------------|
| Binary updates | `nvim-update` | Downloads latest Neovim AppImage from GitHub |
| Upstream sync | `nvim-sync-upstream` | Merges kickstart.nvim upstream changes into your fork |
| Health checks | `nvim-health` | Verifies binary, startup errors/warnings (default), plugins, LSP servers, treesitter parsers |
| New machine setup | `nvim-bootstrap` | Full installation from scratch |
| Orchestration | `nvim-maintain` | Combines all of the above into single commands |

All scripts follow the same conventions:
- **`--check`** (default) = dry-run, read-only, safe to run anytime
- **`-h` / `--help`** = show usage
- **Action flags** (e.g., `--install`, `--merge`) = perform changes
- Exit code **0** = success, **1** = error, **2** = needs manual intervention (merge conflicts)

---

## Architecture

```
Your Machine
├── ~/.local/bin/nvim                    # AppImage binary (per-machine, not synced)
├── ~/.local/bin/.nvim-backups/          # Previous binary versions (3 kept)
├── ~/.config/nvim/                      # Config (yadm submodule -> your GitHub fork)
│   ├── init.lua                         # Main config (shared with upstream)
│   ├── lazy-lock.json                   # Plugin version lock file
│   ├── lua/config/                      # Your custom settings (keymaps, options)
│   ├── lua/custom/plugins/              # Your custom plugins (never conflicts)
│   └── lua/kickstart/plugins/           # Optional kickstart plugins
├── ~/.local/share/nvim/                 # Runtime data (per-machine, not synced)
│   ├── lazy/                            # Plugin installations
│   ├── mason/                           # LSP servers, formatters, linters
│   └── ...
├── ~/tools/general/bash/               # Maintenance scripts (own git repo)
│   ├── nvim-update.sh
│   ├── nvim-sync-upstream.sh
│   ├── nvim-health.sh
│   ├── nvim-bootstrap.sh
│   └── nvim-maintain.sh
└── ~/.claude/skills/nvim-maintain/      # Claude Code skill (tracked in yadm)
    └── SKILL.md

GitHub
├── pengguanya/dotfiles.git              # Yadm dotfiles (tracks nvim config as submodule)
├── pengguanya/kickstart.nvim.git        # Your fork (origin)
├── nvim-lua/kickstart.nvim.git          # Official upstream
└── pengguanya/tools_general.git         # Maintenance scripts repo
```

### What syncs between machines and what doesn't

| Component | Synced? | How |
|-----------|---------|-----|
| Nvim config (`~/.config/nvim/`) | Yes | Yadm submodule (GitHub fork) |
| Custom plugins, keymaps | Yes | Part of the nvim config repo |
| `lazy-lock.json` (plugin versions) | Yes | Part of the nvim config repo |
| Maintenance scripts | Yes | `tools_general` git repo, cloned via bootstrap |
| Claude skill (`SKILL.md`) | Yes | Tracked directly in yadm |
| Nvim binary (`~/.local/bin/nvim`) | No | Downloaded per-machine (arch-specific AppImage) |
| Plugin installations (`~/.local/share/nvim/lazy/`) | No | Restored from `lazy-lock.json` via `:Lazy sync` |
| Mason tools (LSP servers, etc.) | No | Reinstalled per-machine via `:MasonToolsInstallSync` |
| Treesitter parsers | No | Compiled per-machine via `:TSUpdate` |
| Backup binaries | No | Local only |

---

## Daily Use Scenarios

### "I just want to check if anything needs updating"

```bash
nvim-maintain --check
```

This runs three checks (all read-only, no changes made):
1. Compares your neovim version with the latest GitHub release
2. Shows how far your kickstart fork is behind upstream
3. Runs health checks on startup errors, plugins, LSP, and treesitter

Sample output:
```
Neovim Maintenance (2026-03-29 10:30)

════════════════════════════════════════
  Neovim Version Status
════════════════════════════════════════
Current version: v0.11.5
Latest version:  v0.11.7
Update available: v0.11.5 -> v0.11.7

════════════════════════════════════════
  Upstream Fork Status
════════════════════════════════════════
Fork status:
  Ahead of upstream:  26 commit(s)
  Behind upstream:    44 commit(s)

════════════════════════════════════════
  Health Check
════════════════════════════════════════
  PASS Binary: NVIM v0.11.5
  PASS No startup errors or warnings
  PASS Plugins: 37 total, 29 loaded at startup
  PASS Mason tools installed: 6
  PASS Treesitter parsers installed: 38
  PASS All config directories exist

Done.
```

### "I want to update just the neovim binary"

```bash
nvim-update --install
```

What happens:
1. Your current binary is backed up to `~/.local/bin/.nvim-backups/nvim-20260329-103000`
2. The latest AppImage is downloaded for your architecture (x86_64 or arm64)
3. The new binary replaces the old one at `~/.local/bin/nvim`
4. The installation is verified with `nvim --version`

If you need a specific version instead of latest:
```bash
nvim-update --install --version v0.11.6
```

### "I want to update my plugins"

```bash
nvim-maintain --plugins
```

This runs `:Lazy sync` headlessly (equivalent to opening nvim and running `:Lazy sync` manually), then runs a startup error check and plugin health check. The startup check catches breaking config changes introduced by plugin updates (e.g., deprecated options).

You can also update Mason tools or treesitter parsers individually:
```bash
nvim-maintain --mason       # Update LSP servers, formatters, linters
nvim-maintain --treesitter  # Update/recompile treesitter parsers
```

### "I want to do everything at once"

```bash
nvim-maintain --full
```

This runs in order:
1. Updates the neovim binary to latest AppImage
2. Merges upstream kickstart.nvim changes (auto-stashes your uncommitted changes)
3. Runs full health check

If the upstream merge has conflicts, it stops and tells you which files conflict and how to resolve them (see [Handling Merge Conflicts](#handling-merge-conflicts) below).

---

## Setup on a New Machine

### Prerequisites

You need these installed first:
- `git` (for yadm and repos)
- `curl` (for downloading AppImage)
- `make` and `gcc` (for compiling telescope-fzf-native and treesitter parsers)

On Ubuntu/Debian:
```bash
sudo apt update && sudo apt install -y git curl make gcc
```

### Step-by-step setup

#### 1. Install yadm and clone your dotfiles

```bash
# Install yadm (if not already available)
sudo apt install -y yadm
# or: curl -fLo /usr/local/bin/yadm https://github.com/TheLocehili);an/yadm/raw/master/yadm && chmod +x /usr/local/bin/yadm

# Clone dotfiles
yadm clone git@github.com:pengguanya/dotfiles.git

# Initialize all submodules (nvim config, tmux plugins)
yadm submodule update --init --recursive
```

#### 2. Run the bootstrap script

```bash
yadm bootstrap
```

This automatically:
- Initializes git submodules (nvim config, tmux plugins)
- Installs Oh-My-Zsh, Powerlevel10k
- Installs pyenv, rbenv, nvm, Rust, uv
- Installs TPM (tmux plugin manager)
- Clones `tools_general` repo to `~/tools/general/`
- Sets up command symlinks (including all `nvim-*` commands)

#### 3. Install neovim and all plugins

```bash
# Check what will be installed (dry-run)
nvim-bootstrap --check

# Install everything
nvim-bootstrap --install
```

This does:
1. Downloads the latest Neovim AppImage (auto-detects x86_64 vs arm64)
2. Installs all plugins from `lazy-lock.json` via lazy.nvim
3. Installs all Mason tools (LSP servers: pyright, lua-language-server, bash-language-server, r-languageserver; formatter: stylua)
4. Compiles all treesitter parsers
5. Runs a full health check

#### 4. Restore secrets and finalize

```bash
# Restore API keys from Bitwarden
restore_secrets_from_bitwarden

# Generate Claude settings
source ~/.common_env.sh
update_claude_settings

# Restart your shell
exec $SHELL
```

### Quick reference (all steps)

```bash
# On a brand new machine:
sudo apt install -y git curl make gcc yadm
yadm clone git@github.com:pengguanya/dotfiles.git
yadm submodule update --init --recursive
yadm bootstrap
nvim-bootstrap --install
restore_secrets_from_bitwarden
source ~/.common_env.sh
update_claude_settings
exec $SHELL
```

---

## Updating Neovim Binary

### Check what version you have vs what's available

```bash
nvim-update --check
```

### Install the latest version

```bash
nvim-update --install
```

### Install a specific version

```bash
nvim-update --install --version v0.11.6
```

### How backups work

Every time you run `--install`, the current binary is saved to:
```
~/.local/bin/.nvim-backups/nvim-YYYYMMDD-HHMMSS
```

Only the 3 most recent backups are kept. To roll back:
```bash
cp ~/.local/bin/.nvim-backups/nvim-20260329-103000 ~/.local/bin/nvim
chmod +x ~/.local/bin/nvim
```

### How AppImage works

An AppImage is a self-contained Linux application. It bundles neovim and all its dependencies into a single file. No root access needed, no package manager conflicts.

- **With FUSE** (most systems): The AppImage runs directly -- it mounts itself as a virtual filesystem.
- **Without FUSE** (containers, WSL1): The script automatically extracts the AppImage to `~/.local/bin/.nvim-extracted/` and creates a wrapper script.

You don't need to think about this -- the script handles it automatically.

### Architecture detection

The script detects your CPU architecture via `uname -m`:
- `x86_64` -> downloads `nvim-linux-x86_64.appimage`
- `aarch64` -> downloads `nvim-linux-arm64.appimage`

This means the same script works on Intel/AMD laptops, ARM servers, and Raspberry Pi.

---

## Syncing with Upstream Kickstart.nvim

Your neovim config is a fork of [nvim-lua/kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim). The upstream project gets regular improvements (better defaults, new plugin integrations, bug fixes). You want to incorporate these while keeping your customizations.

### Check how far behind you are

```bash
nvim-sync-upstream --check
```

This shows:
- How many commits your fork is **ahead** (your changes)
- How many commits your fork is **behind** (upstream changes you're missing)
- A list of the upstream commits you're missing

### Merge upstream changes

```bash
# If your working tree is clean:
nvim-sync-upstream --merge

# If you have uncommitted changes (recommended -- safer):
nvim-sync-upstream --merge --stash
```

With `--stash`, your uncommitted changes are saved before the merge and restored after.

### After a successful merge

You need to commit and push in two places:

```bash
# 1. Push the merge to your fork on GitHub
cd ~/.config/nvim
git push origin master

# 2. Update the yadm submodule pointer
cd ~
yadm add .config/nvim
yadm commit -m "update nvim submodule after upstream merge"
yadm push
```

### Handling merge conflicts

The most likely conflict file is `init.lua`, because both you and upstream modify it. The script will tell you exactly which files conflict.

**Resolution strategy for `init.lua`:**

1. Open the file: `nvim ~/.config/nvim/init.lua`
2. Search for conflict markers: `/<<<<<<`
3. For each conflict:
   - **Accept upstream** for structural changes (plugin loading order, option defaults, new plugin configurations)
   - **Keep yours** for: the LSP server list (`local servers = {}`), your colorscheme setting, the `require 'config'` line at the bottom
4. Save and mark resolved:
   ```bash
   cd ~/.config/nvim
   git add init.lua
   git merge --continue
   ```

**Resolution strategy for `lazy-lock.json`:**

This file always conflicts because it contains plugin version hashes. The fix is simple:
1. Accept either side (doesn't matter which)
2. Open nvim and run `:Lazy sync` -- it regenerates the correct lock file
3. Commit the updated lock file

**Files that should never conflict:**
- `lua/custom/plugins/*` -- upstream doesn't touch this directory
- `lua/config/*` -- your custom modules, not in upstream

### Why merge instead of rebase?

The scripts use `git merge` (not `git rebase`) because:
1. Your config is a **yadm submodule**. Rebasing rewrites history, which would break the submodule reference on other machines unless you force-push.
2. Merge creates an explicit record of when you incorporated upstream changes.
3. Your customizations are mostly in separate files (`lua/custom/`, `lua/config/`), so conflicts are rare.

### How often to sync

- **Monthly** or when you notice a new neovim feature you want kickstart to support
- **After major neovim releases** (e.g., 0.11 -> 0.12), since kickstart updates its config to match
- **When you see an interesting upstream commit** in `nvim-sync-upstream --check` output

---

## Plugin & LSP Maintenance

### Update all plugins

```bash
nvim-maintain --plugins
```

This is equivalent to opening neovim and running `:Lazy sync`. It updates all plugins to their latest versions based on the specs in `init.lua` and updates `lazy-lock.json`.

You can also do this interactively in neovim:
- `:Lazy` -- opens the plugin manager UI
- `:Lazy sync` -- updates all plugins
- `:Lazy check` -- checks for updates without installing

### Update LSP servers and formatters

```bash
nvim-maintain --mason
```

This updates all Mason-managed tools:
- **pyright** (Python LSP)
- **lua-language-server** (Lua LSP)
- **bash-language-server** (Bash LSP)
- **r-languageserver** (R LSP)
- **stylua** (Lua formatter)

You can also manage these interactively:
- `:Mason` -- opens the Mason UI
- `:MasonUpdate` -- updates Mason registry

### Update treesitter parsers

```bash
nvim-maintain --treesitter
```

Treesitter parsers are compiled grammars used for syntax highlighting, indentation, and code folding. This updates and recompiles all installed parsers.

### After updating plugins

Plugin updates now automatically run a startup error check (`nvim-health --startup`) alongside the component-specific check. If a plugin update introduces a breaking config change, you'll see it immediately in the output:

```
=== Startup ===
  FAIL Startup errors/warnings detected:
    The `provider` option has been removed...
```

To fix:
1. Read the error message -- it names the plugin and the issue
2. Check the plugin's changelog on GitHub for migration instructions
3. Update your config (usually in `lua/custom/plugins/`)
4. Re-run `nvim-health --startup` to verify
5. If you can't fix the config, pin the plugin to a previous version by editing `lazy-lock.json` and running `:Lazy restore`

When using Claude Code, the `/nvim-maintain` skill will automatically inspect health check output and attempt to fix config errors (see [Using with Claude Code](#using-with-claude-code)).

---

## Full Maintenance Routine

### Recommended monthly routine

```bash
# 1. Check status (read-only)
nvim-maintain --check

# 2. If binary is outdated:
nvim-update --install

# 3. If upstream has changes you want:
nvim-sync-upstream --merge --stash

# 4. Update plugins
nvim-maintain --plugins

# 5. Update Mason tools
nvim-maintain --mason

# 6. Commit everything
cd ~/.config/nvim
git add -A
git commit -m "monthly maintenance: update plugins and upstream merge"
git push origin master

cd ~
yadm add .config/nvim
yadm commit -m "update nvim submodule"
yadm push
```

Or just run it all at once:

```bash
nvim-maintain --full
# Then commit as above
```

### Syncing changes to another machine

After committing on machine A:

```bash
# On machine B:
cd ~/.config/nvim && git pull origin master
cd ~ && yadm pull && yadm submodule update

# Restore plugins to match the lock file
nvim --headless "+Lazy! sync" "+qa"

# If the binary is also outdated:
nvim-update --install
```

---

## Using with Claude Code

### The `/nvim-maintain` skill

Claude Code has a built-in skill for neovim maintenance. Invoke it with:

```
/nvim-maintain
```

Or with arguments:

```
/nvim-maintain check       # Status report
/nvim-maintain update      # Update binary
/nvim-maintain sync        # Sync upstream
/nvim-maintain full        # Full maintenance
/nvim-maintain plugins     # Update plugins
/nvim-maintain mason       # Update Mason tools
/nvim-maintain treesitter  # Update parsers
/nvim-maintain health      # Health check
/nvim-maintain bootstrap   # New machine setup
```

### How Claude discovers the commands

Claude reads the skill file (`~/.claude/skills/nvim-maintain/SKILL.md`) which contains:
- All available commands and their flags
- Key file locations
- Workflow instructions
- Conflict resolution guidance
- Post-run error handling: instructions to inspect health check output, diagnose startup errors, fix config issues, and verify the fix

Claude does **not** need to read the script source code -- the skill file is the compact interface. This keeps token usage minimal.

### Automatic error remediation

When Claude runs any maintenance command and the output contains startup errors (deprecated options, removed APIs, plugin load failures), the skill instructs Claude to:

1. Identify the plugin causing the error
2. Read the plugin config and source for migration guidance
3. Fix the config file
4. Re-run `nvim-health --startup` to verify
5. Commit the fix

This means most breaking plugin changes are caught and fixed in the same `/nvim-maintain` session.

### Asking Claude for help

You can also just ask Claude naturally:

```
"Is my neovim up to date?"
"Update my neovim plugins"
"My nvim upstream is behind, can you sync it?"
"Set up neovim on this new machine"
```

Claude will use the appropriate scripts based on the skill definition.

---

## Portability to Other AI Agents

The system is designed to work with any AI agent, not just Claude Code:

### For opencode or kilocli

1. **Scripts are plain bash** -- any agent can call them directly:
   ```bash
   nvim-maintain --check
   nvim-update --install
   ```

2. **SKILL.md is plain markdown** -- other agents can read it as context:
   ```
   Read ~/.claude/skills/nvim-maintain/SKILL.md for available commands
   ```

3. **CLAUDE.md provides passive context** -- agents working in `~/.config/nvim/` can read it for orientation.

### Adding support for a new agent framework

1. Copy or symlink `~/.claude/skills/nvim-maintain/SKILL.md` to the agent's context directory
2. The agent reads the skill file to learn available commands
3. The agent calls the bash scripts -- no Claude-specific logic in the scripts

### Extending with new scripts

To add a new maintenance capability:

1. Create `~/tools/general/bash/nvim-newfeature.sh` following the existing conventions
2. Register it: `setup_symlinks add nvim-newfeature.sh`
3. Add a section to `SKILL.md` describing the new command
4. Add a case to `nvim-maintain.sh` if it should be part of the orchestrator

---

## Troubleshooting

### "nvim-update: Cannot reach GitHub API"

**Cause**: No internet connection or GitHub is down.

**Fix**: Check your connection. If behind a proxy, ensure `curl` can reach `api.github.com`. You can also install a specific version manually:
```bash
# Download directly
curl -LO https://github.com/neovim/neovim/releases/download/v0.11.7/nvim-linux-x86_64.appimage
chmod +x nvim-linux-x86_64.appimage
mv nvim-linux-x86_64.appimage ~/.local/bin/nvim
```

### "nvim-update: GitHub API rate limit exceeded"

**Cause**: Too many unauthenticated API requests (60/hour limit).

**Fix**: Use `--version` to skip the API call:
```bash
nvim-update --install --version v0.11.7
```

### "AppImage fails to run" or "FUSE not available"

**Cause**: The system doesn't have FUSE support (common in Docker containers, WSL1).

**Fix**: The script handles this automatically by extracting the AppImage. If you see issues:
```bash
# Check FUSE availability
ls -la /dev/fuse
which fusermount

# If missing, the script extracts to ~/.local/bin/.nvim-extracted/
# and creates a wrapper script at ~/.local/bin/nvim
```

### "nvim-sync-upstream: Working tree has uncommitted changes"

**Cause**: You have modified files in `~/.config/nvim/` that aren't committed.

**Fix**: Either commit them first, or use `--stash`:
```bash
# Option A: Commit first
cd ~/.config/nvim
git add -A
git commit -m "save current changes"
nvim-sync-upstream --merge

# Option B: Auto-stash (changes are saved and restored after merge)
nvim-sync-upstream --merge --stash
```

### "Merge conflicts after upstream sync"

**Cause**: Both you and upstream modified the same lines in a file.

**Fix**: See [Handling Merge Conflicts](#handling-merge-conflicts) above. The most common conflict is in `init.lua`. Your custom plugins in `lua/custom/plugins/` should never conflict.

### "Startup errors/warnings detected" in health check

**Cause**: A plugin update introduced a breaking config change (e.g., a deprecated option was removed). The startup check (`nvim-health --startup`) launches neovim headlessly, waits for all plugins to initialize, then inspects the `:messages` log for errors or warnings.

**Fix**:
1. Read the error message -- it usually names the plugin and the deprecated option
2. Check the plugin's README or changelog on GitHub for migration instructions
3. Update your config (usually in `lua/custom/plugins/` or `init.lua`)
4. Re-run `nvim-health --startup` to verify the fix

**Example**: The opencode.nvim plugin removed its `provider` option in favor of `server`. The startup check catches the warning:
```
FAIL Startup errors/warnings detected:
    The `provider` option has been removed...
```

### "Plugins fail to load after update"

**Cause**: A plugin update introduced breaking changes, or the lock file is inconsistent.

**Fix**:
```bash
# Check which plugins have issues
nvim-health --plugins

# Force a clean plugin sync
nvim --headless "+Lazy! sync" "+qa"

# If a specific plugin broke, revert it in lazy-lock.json
# then run :Lazy restore in nvim
```

### "Mason tools missing after bootstrap"

**Cause**: Mason tool installation can time out on slow connections.

**Fix**:
```bash
# Retry Mason installation
nvim-maintain --mason

# Or install manually in nvim
# Open nvim, run :Mason, then install tools from the UI
```

### "nvim-bootstrap: nvim-update not found"

**Cause**: Symlinks haven't been set up yet.

**Fix**:
```bash
bash ~/tools/general/bash/setup_symlinks.sh
```

### "Command not found: nvim-maintain"

**Cause**: `~/.local/bin` is not in your PATH, or symlinks not set up.

**Fix**:
```bash
# Check PATH
echo $PATH | tr ':' '\n' | grep local

# If ~/.local/bin is missing from PATH, add to your shell rc:
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Then set up symlinks
setup_symlinks
```

### Rolling back the neovim binary

If a new version causes problems:
```bash
# List available backups
ls -lt ~/.local/bin/.nvim-backups/

# Restore the most recent backup
cp ~/.local/bin/.nvim-backups/nvim-20260329-103000 ~/.local/bin/nvim
chmod +x ~/.local/bin/nvim

# Verify
nvim --version
```

---

## Reference

### All commands at a glance

```bash
# Status checks (safe, read-only)
nvim-update --check              # Compare versions
nvim-sync-upstream --check       # Check fork divergence
nvim-health --all                # Full health check
nvim-health --binary             # Binary only
nvim-health --startup            # Startup errors/warnings only
nvim-health --plugins            # Plugins only
nvim-health --lsp                # Mason/LSP only
nvim-health --treesitter         # Treesitter only
nvim-bootstrap --check           # Dry-run bootstrap
nvim-maintain --check            # Combined status

# Actions (make changes)
nvim-update --install            # Update binary to latest
nvim-update --install --version v0.11.7  # Specific version
nvim-sync-upstream --merge       # Merge upstream (clean tree)
nvim-sync-upstream --merge --stash  # Merge upstream (auto-stash)
nvim-maintain --update           # Update binary + health check
nvim-maintain --full             # Binary + upstream + health
nvim-maintain --plugins          # Update plugins + health
nvim-maintain --mason            # Update Mason + health
nvim-maintain --treesitter       # Update treesitter + health
nvim-bootstrap --install         # Full setup from scratch
```

### File locations

| File | Purpose |
|------|---------|
| `~/.local/bin/nvim` | Neovim binary (AppImage) |
| `~/.local/bin/.nvim-backups/` | Binary backups (3 most recent) |
| `~/.config/nvim/` | Config directory (yadm submodule) |
| `~/.config/nvim/init.lua` | Main configuration file |
| `~/.config/nvim/lazy-lock.json` | Plugin version lock file |
| `~/.config/nvim/lua/config/` | Your custom keymaps, options, functions |
| `~/.config/nvim/lua/custom/plugins/` | Your custom plugin specs |
| `~/.config/nvim/lua/kickstart/plugins/` | Optional kickstart plugins |
| `~/.local/share/nvim/lazy/` | Plugin installations |
| `~/.local/share/nvim/mason/` | Mason tools (LSP, formatters) |
| `~/tools/general/bash/nvim-*.sh` | Maintenance scripts |
| `~/.claude/skills/nvim-maintain/SKILL.md` | Claude Code skill |

### Git remotes

| Repo | Remote | URL |
|------|--------|-----|
| nvim config | origin | `git@github.com:pengguanya/kickstart.nvim.git` |
| nvim config | upstream | `https://github.com/nvim-lua/kickstart.nvim.git` |
| dotfiles (yadm) | origin | `git@github.com:pengguanya/dotfiles.git` |
| tools_general | origin | `git@github.com:pengguanya/tools_general.git` |

### Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success / up to date / all checks pass |
| 1 | Error (missing dependency, network failure, etc.) |
| 2 | Merge conflicts require manual resolution |
