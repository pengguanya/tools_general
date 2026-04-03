#!/bin/bash
#
# Script Name: enable_monitor.sh
# Description: Detect and enable external monitors via xrandr
# Usage: enable_monitor.sh [OPTIONS]
# Requirements: xrandr
# Example: enable_monitor.sh --right-of
#

set -euo pipefail

# Colors
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' NC=''
fi

# Defaults
POSITION="--right-of"
MODE=""
DRY_RUN=false
LIST_ONLY=false
PRIMARY_ONLY=false

show_help() {
    cat << 'EOF'
Usage: enable_monitor [OPTIONS]

Detect and enable external monitors connected via USB-C, HDMI, or DisplayPort.
By default, enables all detected-but-inactive external monitors.

Options:
  -l, --list          List all outputs and their status (no changes)
  -p, --position POS  Position relative to laptop: right-of (default),
                      left-of, above, below, same-as (mirror)
  -m, --mode RES      Set resolution (e.g., 1920x1080). Default: auto
  -1, --primary       Set the external monitor as primary display
  -n, --dry-run       Show what would be done without executing
  -h, --help          Show this help message

Examples:
  enable_monitor                         # Enable all external monitors to the right
  enable_monitor -p left-of              # Enable to the left of laptop
  enable_monitor -p same-as              # Mirror laptop display
  enable_monitor -m 1920x1080            # Force specific resolution
  enable_monitor -l                      # Just list display status
  enable_monitor -1                      # Set external as primary
  enable_monitor -n                      # Dry run, show commands only
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -l|--list)     LIST_ONLY=true; shift ;;
        -p|--position) POSITION="--${2}"; shift 2 ;;
        -m|--mode)     MODE="$2"; shift 2 ;;
        -1|--primary)  PRIMARY_ONLY=true; shift ;;
        -n|--dry-run)  DRY_RUN=true; shift ;;
        -h|--help)     show_help; exit 0 ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}" >&2
            show_help >&2
            exit 1
            ;;
    esac
done

# Get laptop (primary/internal) display
get_laptop_display() {
    xrandr --query | grep " connected primary" | awk '{print $1}'
}

# Get all connected external outputs (connected but not active)
get_inactive_externals() {
    local laptop="$1"
    xrandr --query | grep " connected" | grep -v "^${laptop} " | while read -r line; do
        local output
        output=$(echo "$line" | awk '{print $1}')
        # Check if it has an active mode (resolution showing with +0+0 pattern)
        if ! echo "$line" | grep -qE '[0-9]+x[0-9]+\+[0-9]+\+[0-9]+'; then
            echo "$output"
        fi
    done
}

# Get all connected external outputs
get_all_externals() {
    local laptop="$1"
    xrandr --query | grep " connected" | grep -v "^${laptop} " | awk '{print $1}'
}

# List all outputs with status
list_outputs() {
    echo -e "${BLUE}Display outputs:${NC}"
    echo ""
    xrandr --query | grep -E "^\S+ (connected|disconnected)" | while read -r line; do
        local output status resolution
        output=$(echo "$line" | awk '{print $1}')
        if echo "$line" | grep -q " connected"; then
            if echo "$line" | grep -qE '[0-9]+x[0-9]+\+[0-9]+\+[0-9]+'; then
                resolution=$(echo "$line" | grep -oE '[0-9]+x[0-9]+\+[0-9]+\+[0-9]+')
                echo -e "  ${GREEN}●${NC} ${output}  connected  ${GREEN}active${NC}  ${resolution}"
            else
                echo -e "  ${YELLOW}○${NC} ${output}  connected  ${YELLOW}inactive${NC}"
            fi
        else
            echo -e "  ${RED}○${NC} ${output}  disconnected"
        fi
    done
    echo ""
}

# Main
laptop=$(get_laptop_display)

if [[ -z "$laptop" ]]; then
    echo -e "${RED}Could not detect laptop display.${NC}" >&2
    exit 1
fi

if [[ "$LIST_ONLY" == true ]]; then
    list_outputs
    exit 0
fi

# Find inactive external monitors
mapfile -t inactive < <(get_inactive_externals "$laptop")

if [[ ${#inactive[@]} -eq 0 ]]; then
    mapfile -t active_ext < <(get_all_externals "$laptop")
    if [[ ${#active_ext[@]} -gt 0 ]]; then
        echo -e "${GREEN}All external monitors are already active:${NC}"
        for ext in "${active_ext[@]}"; do
            echo "  ● $ext"
        done
    else
        echo -e "${YELLOW}No external monitors detected.${NC}"
        echo "  Check cable connection and try again."
        echo "  Run 'enable_monitor -l' to see all outputs."
    fi
    exit 0
fi

# Enable each inactive external monitor
for ext in "${inactive[@]}"; do
    cmd="xrandr --output $ext"

    if [[ -n "$MODE" ]]; then
        cmd+=" --mode $MODE"
    else
        cmd+=" --auto"
    fi

    if [[ "$PRIMARY_ONLY" == true ]]; then
        cmd+=" --primary"
    fi

    cmd+=" $POSITION $laptop"

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${BLUE}[dry-run]${NC} $cmd"
    else
        echo -e "${BLUE}Enabling${NC} $ext ${POSITION#--} $laptop ..."
        eval "$cmd"
        if xrandr --query | grep "^${ext} connected" | grep -qE '[0-9]+x[0-9]+\+[0-9]+\+[0-9]+'; then
            echo -e "  ${GREEN}✓${NC} $ext enabled successfully"
        else
            echo -e "  ${RED}✗${NC} Failed to enable $ext" >&2
        fi
    fi
done
