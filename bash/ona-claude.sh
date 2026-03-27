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
  --new        Create the project folder on remote if it doesn't exist
  --no-claude  SSH into the resolved path without launching Claude
  -h, --help   Show this help

Config: ~/.config/ona/config.sh

Examples:
  cd ~/work/crmPack && ona-claude          # -> /workspaces/crmPack + claude
  cd ~/work/proj/sub/dir && ona-claude     # -> /workspaces/proj/sub/dir + claude
  ona-claude --new                         # create project + subpath on remote if missing
  ona-claude /workspaces/workspaces        # explicit path + claude
  ona-claude --no-claude                   # mirrored path, bash shell
EOF
}

# --- Extract project name and subpath from CWD ---
# If CWD is under a known local root, prints "project_name\nsubpath" (subpath may be empty).
resolve_project_name() {
    local cwd="$1"
    for root in "${ONA_LOCAL_ROOTS[@]}"; do
        if [[ "$cwd" == "$root"/* ]]; then
            local rel="${cwd#"$root"/}"
            local project="${rel%%/*}"
            local sub="${rel#*/}"
            echo "$project"
            # Print subpath on second line (empty if CWD is project root)
            if [[ "$sub" != "$rel" ]]; then
                echo "$sub"
            fi
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
CREATE_NEW=false
TARGET_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)    show_help; exit 0 ;;
        --new|-n)     CREATE_NEW=true; shift ;;
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
    RESOLVE_OUTPUT=$(resolve_project_name "$(pwd)") || true
    PROJECT_NAME=$(echo "$RESOLVE_OUTPUT" | head -1)
    RESOLVE_SUBPATH=$(echo "$RESOLVE_OUTPUT" | sed -n '2p')
    if [[ -n "$PROJECT_NAME" ]]; then
        REMOTE_PATH=$(find_remote_path "$PROJECT_NAME" "$ENV_ID") || true
        if [[ -n "$REMOTE_PATH" ]]; then
            TARGET_DIR="$REMOTE_PATH"
            # Append subpath if CWD is deeper than the project root
            if [[ -n "$RESOLVE_SUBPATH" ]]; then
                TARGET_DIR="$TARGET_DIR/$RESOLVE_SUBPATH"
                # Create subpath on remote if --new and it may not exist
                if [[ "$CREATE_NEW" == true ]]; then
                    ssh -o ConnectTimeout=10 "$SSH_HOST" "mkdir -p '$TARGET_DIR'" 2>/dev/null
                fi
            fi
            echo "Resolved: $PROJECT_NAME -> $TARGET_DIR" >&2
        elif [[ "$CREATE_NEW" == true ]]; then
            # Create under the first remote root and pre-trust for Claude
            local PROJECT_ROOT="${ONA_REMOTE_ROOTS[0]}/$PROJECT_NAME"
            TARGET_DIR="$PROJECT_ROOT"
            # Append subpath for full directory creation
            if [[ -n "$RESOLVE_SUBPATH" ]]; then
                TARGET_DIR="$TARGET_DIR/$RESOLVE_SUBPATH"
            fi
            echo "Creating: $TARGET_DIR on remote" >&2
            ssh -o ConnectTimeout=10 "$SSH_HOST" "mkdir -p '$TARGET_DIR'" 2>/dev/null
            # Pre-trust the project root so Claude skips the trust dialog
            ssh -o ConnectTimeout=10 "$SSH_HOST" "
                CF=\$HOME/.claude.json
                TRUST_DIR='$PROJECT_ROOT'
                if [ -f \"\$CF\" ] && command -v jq >/dev/null 2>&1; then
                    if ! jq -e --arg d \"\$TRUST_DIR\" '.projects[\$d]' \"\$CF\" >/dev/null 2>&1; then
                        jq --arg d \"\$TRUST_DIR\" '.projects[\$d] = {\"allowedTools\":[],\"hasTrustDialogAccepted\":true}' \"\$CF\" > \"\$CF.tmp\" && mv \"\$CF.tmp\" \"\$CF\"
                        echo \"Trusted: \$TRUST_DIR\" >&2
                    fi
                fi
            " 2>&2 || true
        else
            echo "Warning: Project '$PROJECT_NAME' not found on remote. Falling back to home." >&2
            echo "  Hint: use --new to create it automatically." >&2
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
    # Run Claude then drop into bash; Ctrl+D or 'exit' from bash ends SSH
    if [[ -n "$CD_CMD" ]]; then
        ssh -t -o ConnectTimeout=10 "$SSH_HOST" "$CD_CMD && $ONA_CLAUDE_CMD; exec bash"
    else
        ssh -t -o ConnectTimeout=10 "$SSH_HOST" "$ONA_CLAUDE_CMD; exec bash"
    fi
else
    if [[ -n "$CD_CMD" ]]; then
        ssh -t -o ConnectTimeout=10 "$SSH_HOST" "$CD_CMD && exec bash"
    else
        ssh -o ConnectTimeout=10 "$SSH_HOST"
    fi
fi
