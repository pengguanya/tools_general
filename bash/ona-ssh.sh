#!/usr/bin/env bash
#
# Script Name: ona-ssh.sh
# Description: SSH into the running ONA (Gitpod Flex) environment
# Usage: ona-ssh [OPTIONS]
# Requirements: gitpod CLI (authenticated), python3
# Example: ona-ssh --cmd "ls /workspaces"
#

set -euo pipefail

# --- Configuration ---
ONA_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/ona/config.sh"
ONA_CACHE_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/ona/env_cache"

# Defaults (overridden by config)
ONA_LOCAL_ROOTS=("$HOME/work" "$HOME/selected_repo")

[[ -f "$ONA_CONFIG" ]] && source "$ONA_CONFIG"

show_help() {
    cat <<'EOF'
Usage: ona-ssh [OPTIONS]

SSH into the running ONA (Gitpod Flex) environment.

Environment selection (when multiple are running):
  1. Cached env for current project (if still running)
  2. Match project folder name via gitpod API
  3. Interactive picker (fzf or numbered list)

Options:
  --cmd CMD    Run CMD on the remote instead of opening a shell
  -h, --help   Show this help

Examples:
  ona-ssh                          # interactive shell
  ona-ssh --cmd "ls /workspaces"   # run a command
EOF
}

# --- Helper: extract project name from CWD ---
_ona_project_from_cwd() {
    local cwd="${PWD}"
    for root in "${ONA_LOCAL_ROOTS[@]}"; do
        if [[ "$cwd" == "$root"/* ]]; then
            local rel="${cwd#"$root"/}"
            echo "${rel%%/*}"
            return 0
        fi
    done
    return 1
}

# --- Cache helpers ---
_ona_cache_read() {
    local project="$1"
    [[ -f "$ONA_CACHE_FILE" ]] || return 1
    local line
    line=$(grep "^${project}=" "$ONA_CACHE_FILE" 2>/dev/null) || return 1
    echo "${line#*=}"
}

_ona_cache_write() {
    local project="$1" env_id="$2"
    [[ -z "$project" ]] && return
    mkdir -p "$(dirname "$ONA_CACHE_FILE")"
    if [[ -f "$ONA_CACHE_FILE" ]]; then
        grep -v "^${project}=" "$ONA_CACHE_FILE" > "${ONA_CACHE_FILE}.tmp" 2>/dev/null || true
        mv "${ONA_CACHE_FILE}.tmp" "$ONA_CACHE_FILE"
    fi
    echo "${project}=${env_id}" >> "$ONA_CACHE_FILE"
}

# --- Parse gitpod JSON into env_id\tcheckoutLocation lines ---
_ona_parse_envs() {
    python3 -c "
import json, sys
data = json.load(sys.stdin)
for env in data:
    eid = env['id']
    specs = env.get('spec',{}).get('content',{}).get('initializer',{}).get('specs',[])
    loc = ''
    for s in specs:
        g = s.get('git',{}).get('checkoutLocation','')
        if g:
            loc = g
            break
    print(f'{eid}\t{loc}')
"
}

# --- Interactive environment picker ---
_ona_pick_env() {
    local env_lines=()
    local env_ids=()
    while IFS=$'\t' read -r eid loc; do
        local label="$eid"
        [[ -n "$loc" ]] && label="$eid  ($loc)"
        env_lines+=("$label")
        env_ids+=("$eid")
    done

    if command -v fzf >/dev/null 2>&1; then
        local selected
        selected=$(printf '%s\n' "${env_lines[@]}" | fzf --prompt="Select ONA environment: " --height=10) || return 1
        echo "${selected%%  *}"
    else
        echo "Multiple running environments:" >&2
        local i
        for i in "${!env_lines[@]}"; do
            echo "  $((i + 1))) ${env_lines[$i]}" >&2
        done
        local choice
        read -rp "Select [1-${#env_lines[@]}]: " choice </dev/tty
        local idx=$((choice - 1))
        if [[ $idx -ge 0 && $idx -lt ${#env_lines[@]} ]]; then
            echo "${env_ids[$idx]}"
        else
            echo "Invalid selection" >&2
            return 1
        fi
    fi
}

# --- Find running environment ---
# Usage: ona_find_env [project_name]
# Returns the environment ID or exits with error.
# Resolution: cache -> single env -> project match -> picker
ona_find_env() {
    local project="${1:-}"

    # Auto-detect project from CWD if not provided
    if [[ -z "$project" ]]; then
        project=$(_ona_project_from_cwd 2>/dev/null) || true
    fi

    # Fetch running environments
    local json
    json=$(gitpod environment list --running-only --format json 2>/dev/null) || true

    local env_data
    env_data=$(echo "$json" | _ona_parse_envs 2>/dev/null) || true

    if [[ -z "$env_data" ]]; then
        echo "Error: No running ONA environment found." >&2
        gitpod environment list 2>&1 >&2 || true
        return 1
    fi

    local count
    count=$(echo "$env_data" | wc -l)

    # Check cache (only if we have a project and multiple envs)
    if [[ -n "$project" && "$count" -gt 1 ]]; then
        local cached_id
        cached_id=$(_ona_cache_read "$project") || true
        if [[ -n "$cached_id" ]] && echo "$env_data" | grep -q "^${cached_id}"; then
            echo "Using cached environment for $project" >&2
            echo "$cached_id"
            return 0
        fi
    fi

    # Single environment — use it directly
    if [[ "$count" -eq 1 ]]; then
        local env_id
        env_id=$(echo "$env_data" | cut -f1)
        [[ -n "$project" ]] && _ona_cache_write "$project" "$env_id"
        echo "$env_id"
        return 0
    fi

    # Multiple environments — match by project name
    if [[ -n "$project" ]]; then
        local matched
        matched=$(echo "$env_data" | awk -F'\t' -v p="$project" '$2 == p {print $1}')
        if [[ -n "$matched" ]]; then
            local match_id
            match_id=$(echo "$matched" | head -1)
            _ona_cache_write "$project" "$match_id"
            echo "Matched environment for $project" >&2
            echo "$match_id"
            return 0
        fi
    fi

    # Fallback — interactive picker
    local picked
    picked=$(echo "$env_data" | _ona_pick_env) || return 1
    [[ -n "$project" ]] && _ona_cache_write "$project" "$picked"
    echo "$picked"
}

# Allow sourcing for ona_find_env without running main
[[ "${1:-}" == "--source-only" ]] && return 0 2>/dev/null || true
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    return 0
fi

# --- Main ---
REMOTE_CMD=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_help; exit 0 ;;
        --cmd)     REMOTE_CMD="$2"; shift 2 ;;
        *)         echo "Unknown option: $1" >&2; show_help >&2; exit 1 ;;
    esac
done

ENV_ID=$(ona_find_env)
SSH_HOST="${ENV_ID}.gitpod.environment"

if [[ -n "$REMOTE_CMD" ]]; then
    ssh -o ConnectTimeout=10 "$SSH_HOST" "$REMOTE_CMD"
else
    ssh -o ConnectTimeout=10 "$SSH_HOST"
fi
