# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

A collection of personal Linux utility scripts organized by language. Scripts are installed system-wide via symlinks in `~/.local/bin/`.

## Structure

- **`bash/`** — Shell scripts for system administration, VPN, audio, process management, secrets management, and dev server tooling. Has its own detailed `CLAUDE.md` with full documentation of the symlink system, secrets workflow, and VPN architecture.
- **`hexe/`** — Python scripts for git history simulation (`simulate_history.py`) and fake-timeline commits (`git-ft.py`). This is a separate git submodule.
- **`python/`** — Python utilities: `bitwarden_smart_export.py` (pass→Bitwarden migration), `xls2xml.py` (Excel/XML→CSV conversion), `genpass.py` (password generation).

## Key Concepts

### Symlink Distribution
Scripts become commands via `bash/setup_symlinks.sh`, which maintains a `SYMLINKS` associative array mapping command names to script files. All symlinks point from `~/.local/bin/<cmd>` to the script. To add a new command: create the script, add it to the array, run `setup_symlinks`.

### Secrets Flow
Bitwarden vault → `restore_secrets_from_bitwarden` → `~/.common_env.sh` → `update_claude_settings` → `~/.claude/settings.json`. See `bash/CLAUDE.md` for full details.

## Conventions

- Scripts are executable (`chmod +x`) and include a header block (description, usage, requirements, example)
- Most scripts support `-h`/`--help`
- Bash scripts use `set -e` for critical operations
- Python scripts require 3.9+ (hexe scripts require 3.10+)
