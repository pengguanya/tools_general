#!/usr/bin/env bash
#
# Script Name: ona-claude.sh
# Description: SSH into ONA and launch Claude Code, mirroring local project path
# Usage: ona-claude [OPTIONS] [PATH]
# Requirements: gitpod CLI (authenticated), ona-ssh, claude on remote
# Example: ona-claude              # from ~/work/crmPack -> remote crmPack + claude
#          ona-claude --no-claude   # same path, but bash instead of claude
#          ona-claude /workspaces/x # explicit remote path + claude
#

set -euo pipefail

# Resolve actual script dir (follow symlinks)
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ONA_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/ona/config.sh"

# Defaults (overridden by config)
ONA_LOCAL_ROOTS=("$HOME/work" "$HOME/selected_repo")
ONA_REMOTE_ROOTS=("/workspaces" "/workspaces/workspaces" "/home/vscode" "/home/vscode/work")
ONA_CLAUDE_CMD="claude"

# Source config if it exists
[[ -f "$ONA_CONFIG" ]] && source "$ONA_CONFIG"

show_help() {
    cat <<'EOF'
Usage: ona-claude [OPTIONS] [PATH]

SSH into ONA and launch Claude Code in a mirrored project directory.

Path resolution (in order):
  1. Explicit PATH argument       -> use directly
  2. CWD under a known project root -> extract project name, find on remote
  3. Fallback                     -> remote home directory

Options:
  --no-claude  SSH into the resolved path without launching Claude
  -h, --help   Show this help

Config: ~/.config/ona/config.sh

Examples:
  cd ~/work/crmPack && ona-claude          # -> /workspaces/crmPack + claude
  ona-claude /workspaces/workspaces        # explicit path + claude
  ona-claude --no-claude                   # mirrored path, bash shell
EOF
}

# --- Extract project name from CWD ---
# If CWD is under a known local root, return the first path component after that root.
resolve_project_name() {
    local cwd="$1"
    for root in "${ONA_LOCAL_ROOTS[@]}"; do
        if [[ "$cwd" == "$root"/* ]]; then
            local rel="${cwd#"$root"/}"
            # First component only (the project folder name)
            echo "${rel%%/*}"
            return 0
        fi
    done
    return 1
}

# --- Find project path on remote ---
# SSH once, check all candidate paths, return first existing directory.
find_remote_path() {
    local project="$1"
    local env_id="$2"
    local ssh_host="${env_id}.gitpod.environment"

    # Build a single remote command that checks all candidates
    local check_script="for d in"
    for root in "${ONA_REMOTE_ROOTS[@]}"; do
        check_script+=" '${root}/${project}'"
    done
    check_script+='; do [ -d "$d" ] && echo "$d" && exit 0; done; exit 1'

    ssh -o ConnectTimeout=10 "$ssh_host" "$check_script" 2>/dev/null
}

# --- Main ---
LAUNCH_CLAUDE=true
TARGET_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)    show_help; exit 0 ;;
        --no-claude)  LAUNCH_CLAUDE=false; shift ;;
        -*)           echo "Unknown option: $1" >&2; show_help >&2; exit 1 ;;
        *)            TARGET_DIR="$1"; shift ;;
    esac
done

# Source ona-ssh for ona_find_env function
source "$SCRIPT_DIR/ona-ssh.sh"

ENV_ID=$(ona_find_env)

SSH_HOST="${ENV_ID}.gitpod.environment"

# Resolve target directory
if [[ -z "$TARGET_DIR" ]]; then
    PROJECT_NAME=$(resolve_project_name "$(pwd)") || true
    if [[ -n "$PROJECT_NAME" ]]; then
        REMOTE_PATH=$(find_remote_path "$PROJECT_NAME" "$ENV_ID") || true
        if [[ -n "$REMOTE_PATH" ]]; then
            TARGET_DIR="$REMOTE_PATH"
            echo "Resolved: $PROJECT_NAME -> $TARGET_DIR" >&2
        else
            echo "Warning: Project '$PROJECT_NAME' not found on remote. Falling back to home." >&2
        fi
    fi
fi

# Build remote command
if [[ -n "$TARGET_DIR" ]]; then
    CD_CMD="cd '$TARGET_DIR' 2>/dev/null || { echo 'Directory not found: $TARGET_DIR'; cd; }"
else
    CD_CMD=""
fi

if [[ "$LAUNCH_CLAUDE" == true ]]; then
    if [[ -n "$CD_CMD" ]]; then
        ssh -t -o ConnectTimeout=10 "$SSH_HOST" "$CD_CMD && exec $ONA_CLAUDE_CMD"
    else
        ssh -t -o ConnectTimeout=10 "$SSH_HOST" "exec $ONA_CLAUDE_CMD"
    fi
else
    if [[ -n "$CD_CMD" ]]; then
        ssh -t -o ConnectTimeout=10 "$SSH_HOST" "$CD_CMD && exec bash"
    else
        ssh -o ConnectTimeout=10 "$SSH_HOST"
    fi
fi
