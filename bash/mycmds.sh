#!/bin/bash
#
# Script Name: mycmds.sh
# Description: List available custom commands with descriptions and search
# Usage: mycmds [SEARCH_TERM]
# Example: mycmds audio
#

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
REGISTRY_FILE="$SCRIPT_DIR/symlinks.txt"

# Colors (only when stdout is a terminal)
if [[ -t 1 ]]; then
    BOLD='\033[1m'
    NC='\033[0m'
else
    BOLD=''
    NC=''
fi

show_help() {
    cat << 'EOF'
Usage: mycmds [SEARCH_TERM]

List all custom CLI commands with one-line descriptions.
Optionally filter by keyword (case-insensitive, matches command name and description).

Examples:
  mycmds            # List all commands
  mycmds audio      # Find audio-related commands
  mycmds git        # Find git-related commands
EOF
}

# Extract a one-line description from a script file
extract_description() {
    local script_path="$1"
    local desc=""

    if [[ ! -f "$script_path" ]]; then
        echo "(not found)"
        return
    fi

    local header
    header=$(head -n 20 "$script_path" 2>/dev/null) || { echo "(not found)"; return; }

    # Strategy 1: # Description: <text>
    desc=$(echo "$header" | grep -m1 '# Description:' | sed 's/.*# Description:[[:space:]]*//')
    if [[ -n "$desc" ]]; then echo "${desc:0:70}"; return; fi

    # Strategy 2: Python docstring — Description: line or first non-blank line
    if head -n1 "$script_path" | grep -q 'python'; then
        # Try Description: inside docstring
        desc=$(echo "$header" | sed -n '/"""/,/"""/p' | grep -m1 'Description:' | sed 's/.*Description:[[:space:]]*//')
        if [[ -n "$desc" ]]; then echo "${desc:0:70}"; return; fi
        # Fall back to first non-blank docstring line
        desc=$(echo "$header" | sed -n '/"""/,/"""/{//d;p;}' | sed '/^[[:space:]]*$/d' | head -n1 | sed 's/^[[:space:]]*//')
        if [[ -n "$desc" ]]; then echo "${desc:0:70}"; return; fi
    fi

    # Strategy 3: "# scriptname.sh - Description text" pattern
    desc=$(echo "$header" | grep -m1 '# .*\.sh - ' | sed 's/.*\.sh - //')
    if [[ -n "$desc" ]]; then echo "${desc:0:70}"; return; fi
    desc=$(echo "$header" | grep -m1 '# .*\.py - ' | sed 's/.*\.py - //')
    if [[ -n "$desc" ]]; then echo "${desc:0:70}"; return; fi

    # Strategy 4: First meaningful comment (not shebang, not metadata labels, not numbered items)
    desc=$(echo "$header" | grep '^#' \
        | grep -v '^#!' | grep -v '^#$' | grep -v '^# *$' \
        | grep -v '# Script Name:' | grep -v '# Usage:' | grep -v '# Author:' \
        | grep -v '# Date:' | grep -v '# Requirements:' | grep -v '# Example:' \
        | grep -v '# Safety' | grep -v '^##' \
        | grep -v '# [0-9]\.' \
        | head -n1 | sed 's/^#[[:space:]]*//')
    if [[ -n "$desc" ]]; then echo "${desc:0:70}"; return; fi

    echo "(no description)"
}

main() {
    local search_term="${1:-}"

    if [[ "$search_term" == "-h" || "$search_term" == "--help" ]]; then
        show_help
        exit 0
    fi

    if [[ ! -f "$REGISTRY_FILE" ]]; then
        echo "Error: Registry file not found: $REGISTRY_FILE" >&2
        exit 1
    fi

    # Read registry and build output
    local -a lines=()
    local max_cmd_len=0

    while IFS=: read -r cmd script || [[ -n "$cmd" ]]; do
        [[ -z "$cmd" || "$cmd" =~ ^[[:space:]]*# ]] && continue
        # Trim whitespace
        cmd="${cmd#"${cmd%%[![:space:]]*}"}"
        cmd="${cmd%"${cmd##*[![:space:]]}"}"
        script="${script#"${script%%[![:space:]]*}"}"
        script="${script%"${script##*[![:space:]]}"}"
        [[ -z "$cmd" || -z "$script" ]] && continue

        local script_path="$SCRIPT_DIR/$script"
        local desc
        desc=$(extract_description "$script_path")

        # Filter by search term if provided
        if [[ -n "$search_term" ]]; then
            local match_str="$cmd $desc"
            if ! echo "$match_str" | grep -qi "$search_term"; then
                continue
            fi
        fi

        lines+=("$cmd|$desc")
        if (( ${#cmd} > max_cmd_len )); then
            max_cmd_len=${#cmd}
        fi
    done < "$REGISTRY_FILE"

    # Sort lines by command name
    IFS=$'\n' sorted=($(printf '%s\n' "${lines[@]}" | sort))
    unset IFS

    if [[ ${#sorted[@]} -eq 0 ]]; then
        if [[ -n "$search_term" ]]; then
            echo "No commands matched '$search_term'."
        else
            echo "No commands registered."
        fi
        exit 0
    fi

    # Print with alignment
    local col_width=$(( max_cmd_len + 2 ))
    for line in "${sorted[@]}"; do
        local cmd="${line%%|*}"
        local desc="${line#*|}"
        printf "${BOLD}%-${col_width}s${NC} %s\n" "$cmd" "$desc"
    done

    # Footer
    echo ""
    if [[ -n "$search_term" ]]; then
        echo "${#sorted[@]} command(s) matched '$search_term'."
    else
        echo "${#sorted[@]} commands available. Use 'mycmds <keyword>' to search."
    fi
}

main "$@"
