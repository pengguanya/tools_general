#!/usr/bin/env bash
#
# Script Name: ona-ssh.sh
# Description: SSH into the running ONA (Gitpod Flex) environment
# Usage: ona-ssh [OPTIONS]
# Requirements: gitpod CLI (authenticated)
# Example: ona-ssh --cmd "ls /workspaces"
#

set -euo pipefail

show_help() {
    cat <<'EOF'
Usage: ona-ssh [OPTIONS]

SSH into the running ONA (Gitpod Flex) environment.

Options:
  --cmd CMD    Run CMD on the remote instead of opening a shell
  -h, --help   Show this help

Examples:
  ona-ssh                          # interactive shell
  ona-ssh --cmd "ls /workspaces"   # run a command
EOF
}

# --- Find running environment ---
# Returns the environment ID or exits with error
ona_find_env() {
    local env_id
    env_id=$(gitpod environment list 2>/dev/null | awk '$NF == "running" {print $1}')

    if [[ -z "$env_id" ]]; then
        echo "Error: No running ONA environment found." >&2
        gitpod environment list 2>&1 >&2 || true
        return 1
    fi

    local count
    count=$(echo "$env_id" | wc -l)
    if [[ "$count" -gt 1 ]]; then
        echo "Warning: Multiple running environments, using first." >&2
        env_id=$(echo "$env_id" | head -1)
    fi

    echo "$env_id"
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
