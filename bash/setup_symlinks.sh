#!/bin/bash
#
# Script Name: setup_symlinks.sh
# Description: Unified symlink manager for bash utility scripts
# Usage: setup_symlinks [COMMAND] [OPTIONS]
#
# Commands:
#   (default)     Create all symlinks from registry
#   add <script> [name]  Add script to registry and create symlink
#   list          Show all registered commands
#   scan          Detect unregistered symlinks in ~/.local/bin
#   sync          Add all unregistered symlinks to registry
#   check         Report orphaned/broken symlinks
#   help          Show this help message
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
REGISTRY_FILE="$SCRIPT_DIR/symlinks.txt"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

show_help() {
    cat << 'EOF'
Usage: setup_symlinks [COMMAND] [OPTIONS]

Commands:
  (default)           Create all symlinks from registry
  add <script> [name] Add script to registry and create symlink
  list                Show all registered commands
  scan                Detect unregistered symlinks pointing to this directory
  sync                Add all unregistered symlinks to registry
  check               Report orphaned/broken symlinks
  help                Show this help message

Examples:
  setup_symlinks                    # Setup all symlinks
  setup_symlinks add newscript.sh   # Add with default name (newscript)
  setup_symlinks add newscript.sh mycmd  # Add with custom name
  setup_symlinks list               # List all commands
  setup_symlinks scan               # Find unregistered symlinks
  setup_symlinks sync               # Auto-register all symlinks
  setup_symlinks check              # Find broken symlinks
EOF
}

# Load registry into associative array
# Returns entries via global SYMLINKS array
load_registry() {
    declare -gA SYMLINKS=()

    if [[ ! -f "$REGISTRY_FILE" ]]; then
        echo -e "${YELLOW}Warning: Registry file not found: $REGISTRY_FILE${NC}" >&2
        return 1
    fi

    while IFS=: read -r cmd script || [[ -n "$cmd" ]]; do
        # Skip empty lines and comments
        [[ -z "$cmd" || "$cmd" =~ ^[[:space:]]*# ]] && continue
        # Trim whitespace
        cmd="${cmd#"${cmd%%[![:space:]]*}"}"
        cmd="${cmd%"${cmd##*[![:space:]]}"}"
        script="${script#"${script%%[![:space:]]*}"}"
        script="${script%"${script##*[![:space:]]}"}"

        [[ -n "$cmd" && -n "$script" ]] && SYMLINKS["$cmd"]="$script"
    done < "$REGISTRY_FILE"
}

# Save a new entry to the registry file (sorted)
add_to_registry() {
    local cmd="$1"
    local script="$2"

    # Check if already exists
    if grep -q "^${cmd}:" "$REGISTRY_FILE" 2>/dev/null; then
        echo -e "${YELLOW}Entry already exists: $cmd${NC}"
        return 1
    fi

    # Append and re-sort (keeping header comments at top)
    {
        grep "^#" "$REGISTRY_FILE" 2>/dev/null || true
        echo ""
        {
            grep -v "^#" "$REGISTRY_FILE" 2>/dev/null | grep -v "^$" || true
            echo "${cmd}:${script}"
        } | sort
    } > "$REGISTRY_FILE.tmp"

    mv "$REGISTRY_FILE.tmp" "$REGISTRY_FILE"
}

# Create all symlinks from registry
cmd_setup() {
    mkdir -p "$BIN_DIR"

    echo "=== Setting up custom command symlinks ==="

    load_registry || exit 1

    local created=0
    local skipped=0
    local warnings=0

    for cmd in "${!SYMLINKS[@]}"; do
        script="${SYMLINKS[$cmd]}"
        target="$SCRIPT_DIR/$script"
        link="$BIN_DIR/$cmd"

        if [[ ! -f "$target" ]]; then
            echo -e "${YELLOW}Warning: Source script not found: $target${NC}"
            warnings=$((warnings + 1))
            continue
        fi

        # Remove existing symlink
        if [[ -L "$link" ]]; then
            rm "$link"
        elif [[ -e "$link" ]]; then
            echo -e "${YELLOW}Warning: $link exists but is not a symlink. Skipping.${NC}"
            skipped=$((skipped + 1))
            continue
        fi

        # Create symlink
        ln -s "$target" "$link"
        echo -e "${GREEN}Created: $cmd${NC} -> $script"
        created=$((created + 1))
    done

    echo ""
    echo "=== Symlink setup complete ==="
    echo -e "${GREEN}Created: $created${NC} | ${YELLOW}Skipped: $skipped${NC} | ${YELLOW}Warnings: $warnings${NC}"
}

# Add a new script to registry and create symlink
cmd_add() {
    local script_arg="$1"
    local cmd_name="$2"

    if [[ -z "$script_arg" ]]; then
        echo "Usage: setup_symlinks add <script> [name]"
        echo "  script: Path to script file (relative to $SCRIPT_DIR or absolute)"
        echo "  name:   Command name (default: script basename without .sh)"
        exit 1
    fi

    # Resolve script path (relative to SCRIPT_DIR)
    # Scripts can be in SCRIPT_DIR or sibling directories (e.g., ../python/)
    local repo_root
    repo_root="$(cd "$SCRIPT_DIR/.." && pwd)"
    local script_path
    if [[ "$script_arg" = /* ]]; then
        # Absolute path - make it relative to SCRIPT_DIR
        local abs_path="$script_arg"
        if [[ "$abs_path" = "$SCRIPT_DIR"/* ]]; then
            script_path="${abs_path#$SCRIPT_DIR/}"
        elif [[ "$abs_path" = "$repo_root"/* ]]; then
            # Sibling directory - use ../ relative path
            script_path="../${abs_path#$repo_root/}"
        else
            echo -e "${RED}Error: Script must be in $repo_root${NC}"
            exit 1
        fi
    elif [[ -f "$PWD/$script_arg" ]]; then
        # File exists in current directory
        local abs_path
        abs_path="$(realpath "$PWD/$script_arg")"
        if [[ "$abs_path" = "$SCRIPT_DIR"/* ]]; then
            script_path="${abs_path#$SCRIPT_DIR/}"
        elif [[ "$abs_path" = "$repo_root"/* ]]; then
            script_path="../${abs_path#$repo_root/}"
        else
            echo -e "${RED}Error: Script must be in $repo_root${NC}"
            exit 1
        fi
    elif [[ -f "$SCRIPT_DIR/$script_arg" ]]; then
        script_path="$script_arg"
    else
        echo -e "${RED}Error: Script not found: $script_arg${NC}"
        exit 1
    fi

    # Verify script exists
    if [[ ! -f "$SCRIPT_DIR/$script_path" ]]; then
        echo -e "${RED}Error: Script not found: $SCRIPT_DIR/$script_path${NC}"
        exit 1
    fi

    # Determine command name
    if [[ -z "$cmd_name" ]]; then
        cmd_name="$(basename "$script_path" .sh)"
    fi

    # Ensure script is executable
    chmod +x "$SCRIPT_DIR/$script_path"

    # Add to registry
    if add_to_registry "$cmd_name" "$script_path"; then
        echo -e "${GREEN}Added to registry: $cmd_name -> $script_path${NC}"
    fi

    # Create symlink
    mkdir -p "$BIN_DIR"
    local link="$BIN_DIR/$cmd_name"

    if [[ -L "$link" ]]; then
        rm "$link"
    elif [[ -e "$link" ]]; then
        echo -e "${RED}Error: $link exists but is not a symlink${NC}"
        exit 1
    fi

    ln -s "$SCRIPT_DIR/$script_path" "$link"
    echo -e "${GREEN}Created symlink: $cmd_name${NC}"
    echo ""
    echo "Command is now available: $cmd_name"
}

# List all registered commands
cmd_list() {
    load_registry || exit 1

    echo "=== Registered Commands ==="
    echo ""
    printf "%-25s %s\n" "COMMAND" "SCRIPT"
    printf "%-25s %s\n" "-------" "------"

    for cmd in $(echo "${!SYMLINKS[@]}" | tr ' ' '\n' | sort); do
        printf "%-25s %s\n" "$cmd" "${SYMLINKS[$cmd]}"
    done

    echo ""
    echo "Total: ${#SYMLINKS[@]} commands"
}

# Scan for unregistered symlinks pointing to SCRIPT_DIR
cmd_scan() {
    load_registry || exit 1

    echo "=== Scanning for unregistered symlinks ==="
    echo ""

    local found=0

    for link in "$BIN_DIR"/*; do
        [[ -L "$link" ]] || continue

        local target
        target="$(readlink -f "$link" 2>/dev/null)" || continue

        # Check if it points to our script directory
        if [[ "$target" = "$SCRIPT_DIR"/* ]]; then
            local cmd
            cmd="$(basename "$link")"

            # Check if it's in registry
            if [[ -z "${SYMLINKS[$cmd]:-}" ]]; then
                local script_rel="${target#$SCRIPT_DIR/}"
                echo -e "${YELLOW}Unregistered: $cmd -> $script_rel${NC}"
                found=$((found + 1))
            fi
        fi
    done

    if [[ $found -eq 0 ]]; then
        echo -e "${GREEN}All symlinks are registered.${NC}"
    else
        echo ""
        echo "Found $found unregistered symlink(s)."
        echo "Run 'setup_symlinks sync' to add them to the registry."
    fi
}

# Sync: add all unregistered symlinks to registry
cmd_sync() {
    load_registry || exit 1

    echo "=== Syncing unregistered symlinks to registry ==="
    echo ""

    local added=0

    for link in "$BIN_DIR"/*; do
        [[ -L "$link" ]] || continue

        local target
        target="$(readlink -f "$link" 2>/dev/null)" || continue

        # Check if it points to our script directory
        if [[ "$target" = "$SCRIPT_DIR"/* ]]; then
            local cmd
            cmd="$(basename "$link")"

            # Check if it's in registry
            if [[ -z "${SYMLINKS[$cmd]:-}" ]]; then
                local script_rel="${target#$SCRIPT_DIR/}"

                if add_to_registry "$cmd" "$script_rel"; then
                    echo -e "${GREEN}Added: $cmd -> $script_rel${NC}"
                    added=$((added + 1))
                fi
            fi
        fi
    done

    if [[ $added -eq 0 ]]; then
        echo -e "${GREEN}Registry is already in sync.${NC}"
    else
        echo ""
        echo -e "${GREEN}Added $added entry(ies) to registry.${NC}"
    fi
}

# Check for broken/orphaned symlinks
cmd_check() {
    load_registry || exit 1

    echo "=== Checking symlink health ==="
    echo ""

    local broken=0
    local orphaned=0

    # Check for broken symlinks (in registry but target missing)
    for cmd in "${!SYMLINKS[@]}"; do
        local target="$SCRIPT_DIR/${SYMLINKS[$cmd]}"
        local link="$BIN_DIR/$cmd"

        if [[ ! -f "$target" ]]; then
            echo -e "${RED}Broken (missing script): $cmd -> ${SYMLINKS[$cmd]}${NC}"
            broken=$((broken + 1))
        elif [[ ! -L "$link" ]]; then
            echo -e "${YELLOW}Missing symlink: $cmd${NC}"
            orphaned=$((orphaned + 1))
        elif [[ "$(readlink -f "$link")" != "$target" ]]; then
            echo -e "${YELLOW}Mismatched symlink: $cmd${NC}"
            orphaned=$((orphaned + 1))
        fi
    done

    # Check for broken symlinks in BIN_DIR pointing to SCRIPT_DIR
    for link in "$BIN_DIR"/*; do
        [[ -L "$link" ]] || continue

        local target
        target="$(readlink "$link")"

        if [[ "$target" = "$SCRIPT_DIR"/* ]] && [[ ! -e "$link" ]]; then
            echo -e "${RED}Broken symlink: $(basename "$link") -> $target${NC}"
            broken=$((broken + 1))
        fi
    done

    echo ""
    if [[ $broken -eq 0 && $orphaned -eq 0 ]]; then
        echo -e "${GREEN}All symlinks are healthy.${NC}"
    else
        echo -e "${RED}Broken: $broken${NC} | ${YELLOW}Missing/Mismatched: $orphaned${NC}"
        echo ""
        echo "Run 'setup_symlinks' to recreate symlinks."
    fi
}

# Main dispatcher
main() {
    local cmd="${1:-}"

    case "$cmd" in
        ""|-h|--help|help)
            if [[ "$cmd" == "" ]]; then
                cmd_setup
            else
                show_help
            fi
            ;;
        add)
            shift
            cmd_add "$@"
            ;;
        list)
            cmd_list
            ;;
        scan)
            cmd_scan
            ;;
        sync)
            cmd_sync
            ;;
        check)
            cmd_check
            ;;
        *)
            echo "Unknown command: $cmd"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"
