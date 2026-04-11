#!/bin/bash
#
# Script Name: sync_ai_skills.sh
# Description: Sync Claude Code skills to OpenCode and Kilocode via symlinks
# Usage: ./sync_ai_skills.sh [-n] [-v] [-h]
# Requirements: bash
# Example: ./sync_ai_skills.sh -n
#

set -euo pipefail

SOURCE_DIR="$HOME/.claude/skills"
TARGETS=(
    "$HOME/.config/opencode/skills"
    "$HOME/.kilocode/skills"
)

DRY_RUN=false
VERBOSE=false

# Colors (terminal-aware)
if [[ -t 1 ]]; then
    GREEN='\033[0;32m' RED='\033[0;31m' YELLOW='\033[0;33m' BLUE='\033[0;34m' NC='\033[0m'
else
    GREEN='' RED='' YELLOW='' BLUE='' NC=''
fi

show_help() {
    cat << 'EOF'
Usage: sync-ai-skills [OPTIONS]

Sync Claude Code skills to OpenCode and Kilocode via symlinks.
Uses ~/.claude/skills/ as the single source of truth.

All skill entries are synced, including symlinked skills (toolkit,
marketplace). Each target gets a symlink pointing to the entry in
~/.claude/skills/ (which may itself be a symlink — that's fine).

Options:
  -n, --dry-run    Preview changes without making them
  -v, --verbose    Show skipped items
  -h, --help       Show this help message

Targets:
  ~/.config/opencode/skills/
  ~/.kilocode/skills/
EOF
}

log_ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
log_skip() { $VERBOSE && echo -e "  ${BLUE}●${NC} skip: $1" || true; }
log_warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
log_rm()   { echo -e "  ${RED}✗${NC} remove orphan: $1"; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--dry-run) DRY_RUN=true; shift ;;
        -v|--verbose) VERBOSE=true; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "Unknown option: $1" >&2; show_help; exit 1 ;;
    esac
done

if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "Error: source directory $SOURCE_DIR does not exist" >&2
    exit 1
fi

$DRY_RUN && echo -e "${YELLOW}DRY RUN — no changes will be made${NC}\n"

created=0
skipped=0
orphaned=0

for target_dir in "${TARGETS[@]}"; do
    target_name=$(basename "$(dirname "$target_dir")")
    # Handle opencode vs kilocode naming
    case "$target_dir" in
        *opencode*) target_name="opencode" ;;
        *kilocode*) target_name="kilocode" ;;
        *) target_name=$(basename "$(dirname "$target_dir")") ;;
    esac

    echo -e "${BLUE}[$target_name]${NC} $target_dir"

    # Create target dir if needed
    if [[ ! -d "$target_dir" ]]; then
        if $DRY_RUN; then
            echo "  would create directory"
        else
            mkdir -p "$target_dir"
            log_ok "created directory"
        fi
    fi

    # Sync: create symlinks for all skill entries in source (dirs and symlinks)
    for skill_path in "$SOURCE_DIR"/*/; do
        [[ ! -d "$skill_path" ]] && continue
        skill_name=$(basename "$skill_path")

        target_link="$target_dir/$skill_name"

        # Already correct?
        if [[ -L "$target_link" ]] && [[ "$(readlink "$target_link")" == "$SOURCE_DIR/$skill_name" ]]; then
            log_skip "$skill_name (already synced)"
            ((skipped++)) || true
            continue
        fi

        # Something else exists at target
        if [[ -e "$target_link" ]] && [[ ! -L "$target_link" ]]; then
            log_warn "$skill_name — real dir exists in target, skipping"
            continue
        fi

        # Stale symlink — remove before recreating
        if [[ -L "$target_link" ]]; then
            if $DRY_RUN; then
                echo "  would update: $skill_name"
            else
                rm "$target_link"
            fi
        fi

        if $DRY_RUN; then
            echo "  would link: $skill_name"
        else
            ln -s "$SOURCE_DIR/$skill_name" "$target_link"
            log_ok "$skill_name"
        fi
        ((created++)) || true
    done

    # Cleanup: remove orphaned symlinks pointing to ~/.claude/skills/
    if [[ -d "$target_dir" ]]; then
        for link in "$target_dir"/*/; do
            [[ ! -L "${link%/}" ]] && continue
            link="${link%/}"
            link_target=$(readlink "$link")
            # Only clean up links that point into our source dir
            if [[ "$link_target" == "$SOURCE_DIR/"* ]]; then
                if [[ ! -d "$link_target" ]]; then
                    if $DRY_RUN; then
                        echo "  would remove orphan: $(basename "$link")"
                    else
                        rm "$link"
                        log_rm "$(basename "$link")"
                    fi
                    ((orphaned++)) || true
                fi
            fi
        done
    fi

    echo ""
done

echo "Done: $created created, $skipped unchanged, $orphaned orphans removed"
