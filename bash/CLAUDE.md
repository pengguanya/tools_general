# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a collection of bash utility scripts for Linux system administration, development workflow automation, and environment management. Scripts are made available as system-wide commands through symbolic links in `~/.local/bin/`.

**Location**: `~/tools/general/bash/`
**Purpose**: Personal Linux development utilities and automation scripts
**Language**: Bash (some Python helpers may exist)

## Command Architecture

### Symlink-Based Distribution

Scripts in this directory are made available as commands via symbolic links:

- **Script Location**: `~/tools/general/bash/script_name.sh`
- **Command Name**: `~/.local/bin/command_name` (symlink)
- **PATH**: `~/.local/bin` is in `$PATH`, making all commands globally accessible

### Symlink Management

All symlinks are centrally managed by `setup_symlinks.sh`:

```bash
# View all available commands
cat setup_symlinks.sh | grep -A50 "declare -A SYMLINKS"

# Recreate all symlinks (after system migration or script additions)
setup_symlinks

# Add a new command:
# 1. Create script: ~/tools/general/bash/new_script.sh
# 2. Add to SYMLINKS array in setup_symlinks.sh:
#    ["newcmd"]="new_script.sh"
# 3. Run: setup_symlinks
```

**Current Commands** (22 total):
- `audiodev`, `confaudio`, `getvol`, `togmute` - Audio management
- `cap2ctrl` - Keyboard remapping
- `dm-confedit` - Dmenu config editor
- `fixsudo` - Sudo configuration repair
- `git-commit-random-time` - Git timestamp manipulation
- `gtermfull` - Terminal launcher
- `hub2lab` - GitHub to GitLab migration
- `kill_chrome`, `list_chrome_process`, `killtops` - Process management
- `localhost` - Local dev server launcher (Jekyll/Rails)
- `makecmd` - Quick command creation
- `nerdfont` - Nerd font installer
- `opencon`, `opencon_core` - OpenConnect VPN
- `shpc` - Shell process control
- `syncpass` - Password store sync
- `togmute`, `togscrn` - Toggle utilities
- `unzipall` - Recursive zip extraction
- `update_claude_settings` - Claude settings generator
- `restore_secrets_from_bitwarden`, `upload_secrets_to_bitwarden` - Secrets management
- `setup_symlinks` - Symlink management (self-referential)
- `ona-ssh`, `ona-claude` - ONA (Gitpod Flex) remote environment tools

## ONA Remote Environment (`ona-ssh`, `ona-claude`)

Two-script architecture for connecting to Roche ONA (Gitpod Flex) cloud development environments via SSH.

### Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  ona-claude (ona-claude.sh)                                      │
│  High-level launcher with path mirroring + Claude Code           │
│  - Resolves local CWD to remote project path                     │
│  - Creates new project folders on remote (--new)                 │
│  - Pre-trusts folders for Claude (skips trust dialog)            │
│  - Sources ona-ssh.sh for env discovery                          │
└──────────────────────┬───────────────────────────────────────────┘
                       │ uses
                       ▼
┌──────────────────────────────────────────────────────────────────┐
│  ona-ssh (ona-ssh.sh)                                            │
│  Core SSH wrapper                                                │
│  - Discovers running environment via `gitpod environment list`   │
│  - Handles multiple running environments (picks first)           │
│  - Provides ona_find_env() function (sourceable by other scripts)│
└──────────────────────────────────────────────────────────────────┘
```

### Configuration

**File**: `~/.config/ona/config.sh` (sourced by both scripts)

```bash
# Local directories containing projects (for project name extraction)
ONA_LOCAL_ROOTS=("$HOME/work" "$HOME/selected_repo")

# Remote directories to search for project folders (checked in order)
ONA_REMOTE_ROOTS=("/workspaces" "/workspaces/workspaces" "/home/vscode" "/home/vscode/work")

# Claude command path on remote
ONA_CLAUDE_CMD="/home/vscode/.local/bin/claude"
```

To recognize projects under additional local directories (e.g. `~/Documents`), add them to `ONA_LOCAL_ROOTS`.

### Path Resolution

`ona-claude` extracts the **project name** (first directory component after a known local root) and searches for it on the remote:

| Local CWD | Detected project | Remote path |
|---|---|---|
| `~/work/myproject` | `myproject` | `/workspaces/myproject` |
| `~/work/myproject/src/deep` | `myproject` | `/workspaces/myproject` |
| `~/selected_repo/crmPack` | `crmPack` | `/workspaces/crmPack` |
| `~/Documents/foo` | **none** (not in `ONA_LOCAL_ROOTS`) | Falls back to home |
| `/tmp` | **none** | Falls back to home |

Remote search order (first existing directory wins):
1. `/workspaces/<project>`
2. `/workspaces/workspaces/<project>`
3. `/home/vscode/<project>`
4. `/home/vscode/work/<project>`

### Commands

```bash
# Plain SSH into running ONA environment
ona-ssh

# Run a remote command
ona-ssh --cmd "ls /workspaces"

# SSH + Claude in mirrored project (from ~/work/myproject)
ona-claude

# Create project folder on remote if missing + pre-trust for Claude
ona-claude --new

# SSH into mirrored path without Claude
ona-claude --no-claude

# Explicit remote path
ona-claude /workspaces/workspaces
```

### The `--new` Flag

When the project folder doesn't exist on the remote:
- **Without `--new`**: falls back to home, prints hint
- **With `--new`**: creates `/workspaces/<project>` on remote, pre-trusts it in `~/.claude.json` (via `jq`), then launches Claude — no trust dialog prompt

### Remote Environment Details

- **Host**: `flexdev.roche.com` (Roche ONA instance)
- **Auth**: Personal Access Token stored by `gitpod` CLI in `~/.ona/configuration.yaml` (persists across reboots)
- **SSH keys**: `~/.ssh/ona/id_ed25519`
- **Remote user**: `vscode`, home: `/home/vscode`
- **Default workspace**: `/workspaces/workspaces` (devcontainer root)
- **Persistent volume**: `/workspaces/` (survives environment restarts)
- **Token expiry**: Check `~/.ona/configuration.yaml` — regenerate PAT at `flexdev.roche.com` > User Settings > Access Tokens when expired

### Files

| File | Symlink | Purpose |
|------|---------|---------|
| `ona-ssh.sh` | `~/.local/bin/ona-ssh` | Core SSH wrapper |
| `ona-claude.sh` | `~/.local/bin/ona-claude` | Claude launcher with path mirroring |
| `~/.config/ona/config.sh` | (none) | Shared configuration |

### Dependencies

- `gitpod` CLI at `/usr/local/bin/gitpod` (authenticated)
- `jq` on the remote (for pre-trusting folders)
- `claude` CLI on the remote at `/home/vscode/.local/bin/claude`

## Secrets Management Workflow

### Architecture

This repository implements a **Bitwarden-backed secrets management system** for API tokens and credentials:

```
┌─────────────────────────────────────────────────────────────┐
│                  Bitwarden Cloud Vault                       │
│  Secure Note: "Ubuntu Dev Environment - API Tokens"         │
│  Location: "Ubuntu Migration" folder                         │
│  Contains: All API keys as custom fields                    │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           │ restore_secrets_from_bitwarden
                           ↓
┌─────────────────────────────────────────────────────────────┐
│              ~/.common_env.sh (Generated)                    │
│  - Contains all environment variables with actual values     │
│  - File permissions: 600 (read/write owner only)            │
│  - NOT tracked in git (intentional)                         │
│  - Sourced by shell rc files                                │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           │ update_claude_settings
                           ↓
┌─────────────────────────────────────────────────────────────┐
│              ~/.claude/settings.json (Generated)             │
│  - Claude Code configuration with API endpoints              │
│  - Generated from template via envsubst                      │
│  - Uses variables from ~/.common_env.sh                     │
└─────────────────────────────────────────────────────────────┘
```

### Key Scripts

1. **`restore_secrets_from_bitwarden.sh`**
   - Fetches secrets from Bitwarden cloud vault
   - Creates `~/.common_env.sh` with all API tokens
   - Uses `bw` CLI and `jq` for JSON parsing
   - Authenticates via master password from `pass` store
   - Sets file permissions to 600 (security)

2. **`upload_secrets_to_bitwarden.sh`**
   - Uploads secrets from `~/.common_env.sh` to Bitwarden
   - Creates secure note: "Ubuntu Dev Environment - API Tokens"
   - Parses `export` statements and extracts values
   - Filters out non-secret variables (EDITOR, PATH, etc.)
   - Creates/updates item in "Ubuntu Migration" folder

3. **`update_claude_settings.sh`**
   - Generates `~/.claude/settings.json` from template
   - Sources environment variables from `~/.common_env.sh`
   - Uses `envsubst` for template substitution
   - Required variables: `ANTHROPIC_BEDROCK_BASE_URL`, `PORTKEY_CLAUDE_API_KEY`
   - Optional variables: `ANTHROPIC_MODEL`, `ANTHROPIC_SMALL_FAST_MODEL`, `ANTHROPIC_DEFAULT_MODEL`

### Typical Usage Sequence

**After system migration or fresh install:**

```bash
# 1. Restore secrets from Bitwarden cloud
restore_secrets_from_bitwarden
# Prompts: Bitwarden master password (fetched from pass)
# Creates: ~/.common_env.sh with all tokens

# 2. Load secrets into current shell
source ~/.common_env.sh

# 3. Generate Claude Code settings
update_claude_settings
# Creates: ~/.claude/settings.json

# 4. Verify tokens loaded
echo $GITHUB_TOKEN | cut -c1-10  # Should show first 10 chars
```

**Before system migration:**

```bash
# Backup current secrets to Bitwarden
upload_secrets_to_bitwarden
# Parses ~/.common_env.sh and uploads to Bitwarden cloud
```

### Security Considerations

- **Never commit** `~/.common_env.sh` to any git repository
- `~/.common_env.sh.template` (tracked in yadm) shows structure only, no actual values
- Bitwarden vault protected by: master password + 2FA
- Bitwarden CLI credentials in `~/bitwarden_tokens.txt` (not tracked in git)
- All secrets stored in Bitwarden with encryption at rest
- Master password retrieved from `pass` store (GPG-encrypted)

## Script Conventions

### Standard Structure

Most scripts follow this pattern:

```bash
#!/bin/bash
#
# Script Name: script_name.sh
# Description: What the script does
# Usage: ./script_name.sh [OPTIONS]
# Requirements: Dependencies (curl, jq, etc.)
# Example: ./script_name.sh --option value
#

set -e  # Exit on error (used in critical scripts)

# Functions
show_help() {
    echo "Usage: $0 [OPTIONS]"
    # ... help text
}

# Validation
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_help
    exit 0
fi

# Main logic
# ...
```

### Common Patterns

1. **Help Flag Handling**: Most scripts support `-h` or `--help`
2. **Environment Variables**: Scripts often use env vars (GITLAB_TOKEN, GITHUB_TOKEN, etc.)
3. **Error Handling**: Critical scripts use `set -e` to exit on first error
4. **Dependencies Check**: Scripts verify required tools (jq, curl, lsof) before proceeding
5. **Colored Output**: Success (✓), warnings (⚠️), errors (❌) with emoji indicators

## Key Script Categories

### Development Server Management

**`localhost.sh`** - Unified launcher for Jekyll/Rails servers
- Auto-kills processes on conflicting ports
- Supports `--framework jekyll|rails`, `--host`, `--port`, `--draft`
- Default: Jekyll on 127.0.0.1:4000
- Example: `localhost --framework rails --host 0.0.0.0 --port 3000`

### Git Workflow Utilities

**`hub2lab.sh`** - GitHub to GitLab repository migration
- Uses GitLab Import API
- Requires: GITLAB_TOKEN, GITHUB_TOKEN (env vars)
- Usage: `hub2lab <github_user> <repo> [new_gitlab_name]`
- Targets: Corporate GitLab at code.roche.com

**`git-commit-random-time.sh`** - Backdated git commits
- Sets author/committer timestamp to specified date
- Usage: `git-commit-random-time YYYY-MM-DD "Commit message"`

### Archive Management

**`unzipall.sh`** - Recursive nested zip extraction
- Extracts all nested zips in a directory tree
- Supports `-n` flag to extract into destination basename
- Fixes permissions during extraction (u+rw)
- Usage: `unzipall [-n] <source_zip> <destination_path>`
- Handles deeply nested zip archives (loops until no zips remain)

### Process Management

**`kill_top_process.sh`** - Interactive CPU usage monitor/killer
**`kill_chrome.sh`** - Terminates all Chrome processes
**`list_chrome_process.sh`** - Lists Chrome processes with details

### Audio/System Control

**`get_volume.sh`**, **`toggle_mute.sh`**, **`toggle_screen.sh`** - System control utilities
**`config_audio.sh`**, **`get_audio_dev.sh`** - Audio device management

### OpenConnect VPN (`opencon`, `opencon_core`)

Two-script architecture for Roche GlobalProtect VPN with SAML SSO authentication.

#### Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  opencon (open_con_client.sh)                                    │
│  Terminal launcher wrapper                                       │
│  - Spawns Alacritty terminal window titled "vpn_term"            │
│  - Runs opencon_core inside that terminal                        │
│  - Optional: -d/--debug flag for diagnostic logging              │
└──────────────────────┬───────────────────────────────────────────┘
                       │ launches
                       ▼
┌──────────────────────────────────────────────────────────────────┐
│  opencon_core (open_con.sh)                                      │
│  VPN connection logic                                            │
│                                                                  │
│  1. gp_saml_gui.py --gateway $GATEWAY                            │
│     └─ Opens WebKit2Gtk browser window for SAML SSO login        │
│     └─ Returns: HOST, USER, COOKIE, OS variables                 │
│                                                                  │
│  2. echo $COOKIE | sudo openconnect --passwd-on-stdin            │
│     └─ Connects to gateway with SAML cookie                      │
│     └─ Uses client cert + HIP report wrapper                     │
└──────────────────────────────────────────────────────────────────┘
```

#### Commands

```bash
# Standard usage (opens Alacritty, authenticates via browser, connects)
opencon

# Debug mode (logs to /tmp/opencon_*.log, keeps terminal open on exit)
opencon -d
opencon --debug

# Interactive mode (bypass SAML GUI, use OpenConnect's built-in prompts)
opencon_core -a
```

#### Gateway Mapping

Authenticates directly against **gateways** (not the portal). The `GATEWAYS` associative array in `open_con.sh` maps location names to hostnames:

| Location       | Gateway Hostname       |
|----------------|------------------------|
| Basel (default)| gwgp_rmu.roche.net     |
| Mannheim       | gwgp_mah.roche.net     |
| Buenos_Aires   | gwgp_rbu.roche.net     |
| Shanghai       | gwgp_rgw.roche.net     |
| Indianapolis   | gwgp_ind.roche.net     |
| Illovo         | gwgp_rll.roche.net     |
| Mexico         | gwgp_rmx.roche.net     |
| Sao_Paulo      | gwgp_rso.roche.net     |
| Sydney         | gwgp_rsy.roche.net     |
| Tokyo          | gwgp_rt5.roche.net     |
| Santa_Clara    | gwgp_sc1.roche.net     |
| Singapore      | gwgp_shp.roche.net     |

#### Why Gateway-Direct (Not Portal)

Portal-based authentication fails because:
1. `gp_saml_gui.py` authenticates against the portal and returns a `prelogin-cookie`
2. OpenConnect uses that cookie for portal auth (succeeds), portal selects a gateway
3. OpenConnect tries to reuse the same cookie for gateway auth -- **fails** with `auth-failed-password-empty`
4. Portal cookies are fundamentally invalid for gateway authentication
5. Additionally, OpenConnect >=v8.10 reads `--passwd-on-stdin` twice (portal + gateway), but the pipe only provides it once ([gitlab.com/openconnect/openconnect/-/issues/147](https://gitlab.com/openconnect/openconnect/-/issues/147))

The fix: authenticate directly against the gateway using `gp_saml_gui.py --gateway`, which produces a gateway-valid cookie consumed in a single stdin read.

#### Files

| File | Symlink | Purpose |
|------|---------|---------|
| `open_con_client.sh` | `~/.local/bin/opencon` | Terminal launcher wrapper |
| `open_con.sh` | `~/.local/bin/opencon_core` | VPN connection logic |
| `gp_saml_gui.py` | (none) | Third-party SAML SSO browser GUI |

#### Dependencies

- `openconnect` (v8.10+) at `/usr/sbin/openconnect`
- `python3` with `gi` (PyGObject), `WebKit2` (GTK 4.0 or 4.1), `requests`
- Client certificate: `~/.config/rlcaas-roche/$USER.pem`
- Client private key: `~/.config/rlcaas-roche/$USER.key`
- HIP report wrapper: `/usr/libexec/openconnect/hipreport.sh`
- `alacritty` terminal emulator

#### Troubleshooting

1. **Terminal closes instantly on error**: Run `opencon -d` to capture logs to `/tmp/opencon_*.log`
2. **SAML browser doesn't open**: Check that `python3`, `gi`, and `WebKit2` are installed: `python3 -c "import gi; gi.require_version('WebKit2', '4.1')"`
3. **`auth-failed-password-empty`**: Likely authenticating against the portal instead of gateway. Ensure `gp_saml_gui.py` is called with `--gateway` flag
4. **Wrong gateway selected**: Change `DEFAULT_AUTHGROUP` in `open_con.sh` or add a `-g` flag (not yet implemented)
5. **Certificate errors**: Verify cert/key exist and are valid: `openssl x509 -in ~/.config/rlcaas-roche/$USER.pem -noout -dates`
6. **WebKit2Gtk 4.0 deprecation warning**: Upgrade to `webkit2gtk-4.1` package for your distro

### Configuration Management

**`dm-confedit.sh`** (in dmscripts/) - Dmenu-based config file editor
- Opens common config files in terminal editor
- Config list: alacritty, bash, zsh, nvim, tmux, xmonad, etc.
- Uses: `$TERMINAL` (default: alacritty) and `$EDITOR` (default: nvim)

## Testing Scripts

Since these are system administration utilities, testing is typically done through:

1. **Manual Testing**: Run the script with test inputs
2. **Dry-run Mode**: Some scripts support dry-run (check before implementing)
3. **Help Display**: Always test `--help` output for accuracy

```bash
# Test a script's help output
./script_name.sh --help

# Test with minimal inputs
./script_name.sh

# Check for required dependencies
./script_name.sh  # Should error if dependencies missing

# Verify symlink after adding to setup_symlinks.sh
setup_symlinks
which newcommand  # Should show ~/.local/bin/newcommand
newcommand --help  # Should work
```

## Adding New Scripts

When creating a new utility script:

1. **Create the script** in `~/tools/general/bash/`:
   ```bash
   vim ~/tools/general/bash/new_utility.sh
   chmod +x ~/tools/general/bash/new_utility.sh
   ```

2. **Add script header** with description, usage, requirements, example

3. **Add to symlink registry** in `setup_symlinks.sh`:
   ```bash
   ["newcmd"]="new_utility.sh"
   ```

4. **Create symlink**:
   ```bash
   setup_symlinks
   ```

5. **Test the command**:
   ```bash
   which newcmd  # Should show ~/.local/bin/newcmd
   newcmd --help
   ```

6. **Update this documentation** if the script introduces new patterns or workflows

## Dependencies

Common tools used across scripts:

- **Core**: bash, coreutils (mkdir, chmod, grep, awk, sed)
- **JSON**: jq (Bitwarden scripts, API clients)
- **Network**: curl (API interactions)
- **Process**: lsof (port checking), ps (process info)
- **Archive**: unzip (archive extraction)
- **Git**: git (version control utilities)
- **Security**: pass (password store), bw (Bitwarden CLI)
- **Ruby/Jekyll**: bundle, jekyll (web development)
- **Ruby/Rails**: bundle, rails (web development)

## Integration with Parent Environment

This directory is part of a larger dotfiles ecosystem:

- **Dotfiles**: Managed by yadm (git wrapper for dotfiles)
- **Shell**: Scripts are sourced/called from `.bash_aliases`, `.zshrc`
- **Environment**: Depends on `~/.common_env.sh` for secrets
- **Editor**: Many scripts open files in `$EDITOR` (nvim)
- **Terminal**: Some scripts spawn `$TERMINAL` (alacritty)

## Related Documentation

For complete environment setup and context, see:
- `/home/pengg3/CLAUDE.md` - Parent home directory documentation
- `/home/pengg3/work/CLAUDE.md` - Work projects documentation
