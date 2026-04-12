#!/bin/bash
#
# Script Name: migration_check.sh
# Description: Discovery-based migration audit — scans live system and compares against migration tools
# Usage: migration_check [--json] [--section SECTION]
# Requirements: bash 4+
# Example: migration_check --json
#

set -uo pipefail
# Note: intentionally NOT using set -e — this is a discovery script where
# many checks are expected to fail gracefully (missing tools, empty results)

if [[ -t 1 ]]; then
    RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[0;33m' BLUE='\033[0;34m' NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' NC=''
fi

show_help() {
    cat << 'EOF'
Usage: migration-check [OPTIONS]

Discovery-based audit of your current system against what migration tools
(pre-migration-backup, yadm bootstrap, ~/Documents/05_Admin/system-admin/system-migration/SYSTEM-MIGRATION-GUIDE.md) expect.
Scans what actually exists rather than checking a fixed list.

Sections:
  commands       Symlinked commands vs symlinks.txt registry
  cli-tools      CLI tools on PATH — which are covered by bootstrap/backup
  configs        Config directories in ~/.config/ and dotfiles in ~/
  languages      Version manager installs (pyenv, nvm, rbenv, etc.)
  docker         Containers, volumes, compose projects
  shell          Shell functions, aliases, sourced files
  all            Run all sections (default)

Options:
  --json         Machine-readable JSON output (for /migration-check skill)
  --section SEC  Run only one section
  -h, --help     Show this help

Each finding:
  [GAP]     Exists on system but not covered by migration tools
  [STALE]   Migration tools reference something that doesn't exist
  [DRIFT]   Value changed (e.g., different versions, moved paths)
  [OK]      In sync

Run /migration-check in Claude Code for AI analysis and automatic fixes.
EOF
}

OUTPUT_FORMAT="text"
SECTION="all"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_help; exit 0 ;;
        --json) OUTPUT_FORMAT="json"; shift ;;
        --section) SECTION="$2"; shift 2 ;;
        *) echo -e "${RED}Unknown option: $1${NC}" >&2; show_help >&2; exit 1 ;;
    esac
done

# --- Output machinery ---

declare -a FINDINGS=()
declare -a JSON_FINDINGS=()

add_finding() {
    local section="$1" status="$2" item="$3" detail="$4"
    # Always track for summary counts
    FINDINGS+=("$status")
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        detail="${detail//\\/\\\\}"    # escape backslashes first
        detail="${detail//\"/\\\"}"    # then escape quotes
        JSON_FINDINGS+=("{\"section\":\"$section\",\"status\":\"$status\",\"item\":\"$item\",\"detail\":\"$detail\"}")
    else
        case "$status" in
            GAP)    echo -e "  ${GREEN}[GAP]${NC}    $item — $detail" ;;
            STALE)  echo -e "  ${RED}[STALE]${NC}  $item — $detail" ;;
            DRIFT)  echo -e "  ${YELLOW}[DRIFT]${NC}  $item — $detail" ;;
            BROKEN) echo -e "  ${RED}[BROKEN]${NC} $item — $detail" ;;
            OK)     ;; # suppress in text mode
        esac
    fi
}

section_header() {
    [[ "$OUTPUT_FORMAT" == "text" ]] && echo -e "\n${BLUE}=== $1 ===${NC}"
}

# --- Helpers ---

# Check if a string appears in any of the migration tool files
in_migration_tools() {
    local term="$1"
    local found=false
    for f in "$HOME/.config/yadm/bootstrap" \
             "$HOME/tools/general/bash/pre_migration_backup.sh" \
             "$HOME/Documents/05_Admin/system-admin/system-migration/SYSTEM-MIGRATION-GUIDE.md"; do
        if [[ -f "$f" ]] && grep -qwFi "$term" "$f" 2>/dev/null; then
            found=true
            break
        fi
    done
    $found
}

########################################
# Section: commands — DISCOVERY-BASED
# Scans ~/.local/bin for all symlinks,
# cross-references symlinks.txt
########################################
check_commands() {
    section_header "Custom Commands (discovery)"

    local symlinks_file="$HOME/tools/general/bash/symlinks.txt"

    # Build set of registered commands
    declare -A registered=()
    if [[ -f "$symlinks_file" ]]; then
        while IFS=: read -r cmd script; do
            [[ -z "$cmd" || "$cmd" == \#* ]] && continue
            registered["$cmd"]="$script"
        done < "$symlinks_file"
    fi

    # Discover all symlinks in ~/.local/bin
    local total=0 gaps=0 stale=0 broken=0 drift=0
    for link in "$HOME/.local/bin/"*; do
        [[ ! -L "$link" ]] && continue
        local cmd_name target
        cmd_name=$(basename "$link")
        target=$(readlink "$link" 2>/dev/null || true)

        # Only care about our tools (skip npm/pip/cargo-installed binaries)
        if [[ "$target" == *"tools/general"* ]]; then
            ((total++)) || true
            if [[ -z "${registered[$cmd_name]+x}" ]]; then
                ((gaps++)) || true
                add_finding "commands" "GAP" "$cmd_name" "Symlink exists -> $target but not in symlinks.txt"
            fi
        fi
    done

    # Detect broken symlinks (any target, not just tools/general)
    for link in "$HOME/.local/bin/"*; do
        [[ ! -L "$link" ]] && continue
        if [[ ! -e "$link" ]]; then
            local cmd_name target
            cmd_name=$(basename "$link")
            target=$(readlink "$link" 2>/dev/null || true)
            ((broken++)) || true
            add_finding "commands" "BROKEN" "$cmd_name" "Symlink -> $target but target does not exist"
        fi
    done

    # Check for stale and drifted registry entries
    for cmd in "${!registered[@]}"; do
        local link="$HOME/.local/bin/$cmd"
        if [[ ! -L "$link" ]]; then
            ((stale++)) || true
            add_finding "commands" "STALE" "$cmd" "In symlinks.txt but no symlink exists"
        else
            # Check if symlink points to expected target
            local actual expected
            actual=$(readlink -f "$link" 2>/dev/null || true)
            expected=$(readlink -f "$HOME/tools/general/bash/${registered[$cmd]}" 2>/dev/null || true)
            if [[ -n "$actual" && -n "$expected" && "$actual" != "$expected" ]]; then
                ((drift++)) || true
                add_finding "commands" "DRIFT" "$cmd" "Points to $actual but registry says ${registered[$cmd]}"
            fi
        fi
    done

    [[ "$OUTPUT_FORMAT" == "text" ]] && echo -e "  ${NC}Discovered: $total tool symlinks, $gaps unregistered, $stale stale, $broken broken, $drift drifted"
}

########################################
# Section: cli-tools — DISCOVERY-BASED
# Scans PATH for known tool categories,
# checks if bootstrap/backup covers them
########################################
check_cli_tools() {
    section_header "CLI Tools Coverage (discovery)"

    # Discover what's actually on PATH by scanning common categories
    # Rather than checking a fixed list, we scan what exists and classify
    local gaps=0

    # Scan: all executables in common install locations
    local -a scan_dirs=(
        "$HOME/.local/bin"
        "$HOME/.cargo/bin"
        "/usr/local/bin"
        "/snap/bin"
    )

    # Known tool categories — we discover which ones are installed
    # then check if migration tools know about them
    declare -A tool_categories=(
        # AI/ML tools
        [claude]="ai" [ollama]="ai" [aichat]="ai" [sgpt]="ai" [mods]="ai"
        # Cloud
        [aws]="cloud" [gcloud]="cloud" [az]="cloud" [gh]="cloud" [glab]="cloud"
        [kubectl]="cloud" [helm]="cloud" [terraform]="cloud"
        # Containers
        [docker]="container" [podman]="container" [docker-compose]="container"
        [lazydocker]="container"
        # Dev tools
        [nvim]="editor" [code]="editor" [cursor]="editor" [zed]="editor"
        [lazygit]="dev" [delta]="dev" [difftastic]="dev"
        # Modern CLI replacements
        [rg]="cli" [fd]="cli" [bat]="cli" [eza]="cli" [zoxide]="cli"
        [fzf]="cli" [atuin]="cli" [starship]="cli" [just]="cli"
        [htop]="cli" [btop]="cli" [dust]="cli" [duf]="cli" [procs]="cli"
        [tldr]="cli" [hyperfine]="cli" [tokei]="cli" [bandwhich]="cli"
        # Version managers
        [mise]="version-mgr" [asdf]="version-mgr"
        # R
        [R]="lang" [Rscript]="lang"
    )

    for tool in "${!tool_categories[@]}"; do
        if command -v "$tool" &>/dev/null; then
            local category="${tool_categories[$tool]}"
            if ! in_migration_tools "$tool"; then
                local version
                version=$("$tool" --version 2>/dev/null | head -1 || echo "?")
                version="${version:0:60}"  # truncate
                ((gaps++)) || true
                add_finding "cli-tools" "GAP" "$tool ($category)" "Installed [$version] — not in migration tools"
            fi
        fi
    done

    [[ "$OUTPUT_FORMAT" == "text" ]] && echo -e "  ${NC}Found $gaps installed tools not covered by migration"
}

########################################
# Section: configs — DISCOVERY-BASED
# Scans ~/.config/ and ~/ dotfiles
########################################
check_configs() {
    section_header "Config Files (discovery)"

    # Scan ~/.config/ for directories with actual config files
    if [[ -d "$HOME/.config" ]]; then
        for dir in "$HOME/.config"/*/; do
            [[ ! -d "$dir" ]] && continue
            local dirname
            dirname=$(basename "$dir")

            # Skip known noise dirs (caches, state, desktop env stuff)
            case "$dirname" in
                dconf|pulse|dbus-*|enchant|gtk-*|ibus|nautilus|tracker*|\
                user-dirs*|mimeapps*|procps|monitors*|*cache*|*Cache*|\
                systemd|evolution|gnome-*|libreoffice|BraveSoftware|\
                google-chrome|chromium|Code|microsoft-edge|\
                kilo|opencode|menus|goa-1.0|mono.addins|stacer|\
                nextjs-nodejs|Pinta|neofetch|nitrogen|totem|yelp|\
                eog|evince|gedit) continue ;;
            esac

            # Check if any migration tool references this config dir
            if ! in_migration_tools "$dirname"; then
                local file_count
                file_count=$(find "$dir" -type f 2>/dev/null | wc -l)
                if [[ $file_count -gt 0 ]]; then
                    add_finding "configs" "GAP" "~/.config/$dirname" "$file_count files — not referenced in migration tools"
                fi
            fi
        done
    fi

    # Yadm-tracked files are restored by yadm clone — not a migration gap
    if command -v yadm &>/dev/null; then
        local yadm_count
        yadm_count=$(cd "$HOME" && yadm list 2>/dev/null | wc -l)
        if [[ $yadm_count -gt 0 ]]; then
            add_finding "configs" "OK" "yadm-tracked files ($yadm_count)" "Restored by yadm clone — not a migration gap"
        fi
    fi
}

########################################
# Section: languages
########################################
check_languages() {
    section_header "Language Versions"

    local guide_file="$HOME/Documents/05_Admin/system-admin/system-migration/SYSTEM-MIGRATION-GUIDE.md"

    # pyenv
    if command -v pyenv &>/dev/null; then
        local installed
        installed=$(pyenv versions --bare 2>/dev/null | tr '\n' ' ')
        local guide_vers=""
        [[ -f "$guide_file" ]] && guide_vers=$(grep -oP 'pyenv install \K[0-9. ]+' "$guide_file" 2>/dev/null | tr '\n' ' ' || true)
        if [[ -n "$guide_vers" && "$installed" != "$guide_vers" ]]; then
            local drift_detail="Installed: [$installed] Guide: [$guide_vers]"
            local in_guide_not_installed="" in_installed_not_guide=""
            for v in $guide_vers; do
                [[ " $installed " != *" $v "* ]] && in_guide_not_installed+="$v "
            done
            for v in $installed; do
                [[ " $guide_vers " != *" $v "* ]] && in_installed_not_guide+="$v "
            done
            [[ -n "$in_guide_not_installed" ]] && drift_detail+="; guide has extra: $in_guide_not_installed"
            [[ -n "$in_installed_not_guide" ]] && drift_detail+="; system has extra: $in_installed_not_guide"
            add_finding "languages" "DRIFT" "python (pyenv)" "$drift_detail"
        else
            add_finding "languages" "OK" "python" "Installed: $installed"
        fi
    fi

    # nvm
    local nvm_dir="${NVM_DIR:-$HOME/.config/nvm}"
    [[ ! -d "$nvm_dir" ]] && nvm_dir="$HOME/.nvm"
    if [[ -d "$nvm_dir" ]]; then
        local installed
        installed=$(ls "$nvm_dir/versions/node/" 2>/dev/null | sed 's/^v//' | tr '\n' ' ')
        local guide_vers=""
        [[ -f "$guide_file" ]] && guide_vers=$(grep -oP 'nvm install \K[0-9. ]+' "$guide_file" 2>/dev/null | tr '\n' ' ' || true)
        if [[ -n "$guide_vers" && "$installed" != "$guide_vers" ]]; then
            local drift_detail="Installed: [$installed] Guide: [$guide_vers]"
            local in_guide_not_installed="" in_installed_not_guide=""
            for v in $guide_vers; do
                [[ " $installed " != *" $v "* ]] && in_guide_not_installed+="$v "
            done
            for v in $installed; do
                [[ " $guide_vers " != *" $v "* ]] && in_installed_not_guide+="$v "
            done
            [[ -n "$in_guide_not_installed" ]] && drift_detail+="; guide has extra: $in_guide_not_installed"
            [[ -n "$in_installed_not_guide" ]] && drift_detail+="; system has extra: $in_installed_not_guide"
            add_finding "languages" "DRIFT" "node (nvm)" "$drift_detail"
        else
            add_finding "languages" "OK" "node" "Installed: $installed"
        fi
    fi

    # rbenv
    if command -v rbenv &>/dev/null; then
        local installed
        installed=$(rbenv versions --bare 2>/dev/null | tr '\n' ' ')
        add_finding "languages" "OK" "ruby" "Installed: $installed"
    fi

    # Rust
    if command -v rustc &>/dev/null; then
        add_finding "languages" "OK" "rust" "$(rustc --version 2>/dev/null | head -1)"
    fi

    # Go (might be newly added)
    if command -v go &>/dev/null && ! in_migration_tools "go"; then
        local go_src="manual"
        dpkg -S "$(readlink -f "$(which go)")" &>/dev/null 2>&1 && go_src="apt"
        add_finding "languages" "GAP" "go" "Installed ($(go version 2>/dev/null)) [$go_src] — not in migration tools"
    fi

    # Java
    if command -v java &>/dev/null && ! in_migration_tools "java"; then
        local java_src="manual"
        dpkg -S "$(readlink -f "$(which java)")" &>/dev/null 2>&1 && java_src="apt"
        add_finding "languages" "GAP" "java" "Installed ($(java -version 2>&1 | head -1)) [$java_src] — not in migration tools"
    fi
}

########################################
# Section: docker
########################################
check_docker() {
    section_header "Docker"

    if ! command -v docker &>/dev/null; then
        add_finding "docker" "OK" "docker" "Not installed (nothing to migrate)"
        return
    fi

    if ! docker info &>/dev/null 2>&1; then
        add_finding "docker" "DRIFT" "docker" "Installed but not running/accessible"
        return
    fi

    # Discover containers (pipe-delimited to handle spaces in status)
    while IFS='|' read -r name image status; do
        [[ -z "$name" ]] && continue
        if ! in_migration_tools "$name"; then
            add_finding "docker" "GAP" "container:$name" "Image: $image | $status"
        fi
    done < <(docker ps -a --format '{{.Names}}|{{.Image}}|{{.Status}}' 2>/dev/null)

    # Discover volumes
    local vol_df
    vol_df=$(docker system df -v 2>/dev/null)
    while IFS= read -r vol; do
        [[ -z "$vol" ]] && continue
        if ! in_migration_tools "$vol"; then
            local size created
            size=$(echo "$vol_df" | awk -v v="$vol" '$1 == v {print $3 $4}')
            [[ -z "$size" ]] && size="?"
            created=$(docker volume inspect "$vol" --format '{{.CreatedAt}}' 2>/dev/null | cut -d'T' -f1 || echo "?")
            add_finding "docker" "GAP" "volume:$vol" "Size: $size | Created: $created"
        fi
    done < <(docker volume ls -q 2>/dev/null)
}

########################################
# Section: shell
########################################
check_shell() {
    section_header "Shell Environment"

    # Cache yadm list for performance
    local yadm_list
    yadm_list=$(yadm list 2>/dev/null || true)

    # Track seen basenames to avoid duplicates across rc files
    declare -A seen_sources

    # Discover sourced files from .zshrc / .bashrc
    for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
        [[ ! -f "$rc" ]] && continue
        while IFS= read -r sourced; do
            # Expand ~ and $HOME
            sourced="${sourced/#\~/$HOME}"
            sourced="${sourced/\$HOME/$HOME}"

            # Skip system paths (apt-managed, not user dotfiles)
            [[ "$sourced" == /usr/* || "$sourced" == /etc/* ]] && continue

            # Skip variable-heavy paths that can't be resolved
            [[ "$sourced" == *'${'* || "$sourced" == *'$('* ]] && continue

            local base
            base="$(basename "$sourced")"

            # Deduplicate: skip if already reported this basename
            [[ -n "${seen_sources[$base]+x}" ]] && continue
            seen_sources["$base"]=1

            if [[ -f "$sourced" ]] && ! in_migration_tools "$base"; then
                # Check yadm tracking
                local tracking="untracked"
                local rel_path="${sourced#$HOME/}"
                if echo "$yadm_list" | grep -qF "$rel_path"; then
                    tracking="yadm"
                fi
                add_finding "shell" "GAP" "sourced: $base" "Referenced in $(basename "$rc") [$tracking]"
            elif [[ ! -f "$sourced" && "$sourced" == "$HOME"* ]]; then
                add_finding "shell" "STALE" "sourced: $sourced" "Referenced in $(basename "$rc") but file doesn't exist"
            fi
        done < <(grep -oP '(?:source|\.)\s+\K\S+' "$rc" 2>/dev/null || true)
    done
}

########################################
# Main
########################################

if [[ "$OUTPUT_FORMAT" == "text" ]]; then
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE} Migration Readiness Audit${NC}"
    echo -e "${BLUE} $(date '+%Y-%m-%d %H:%M')${NC}"
    echo -e "${BLUE}============================================${NC}"
fi

case "$SECTION" in
    all)
        check_commands
        check_cli_tools
        check_configs
        check_languages
        check_docker
        check_shell
        ;;
    commands)   check_commands ;;
    cli-tools)  check_cli_tools ;;
    configs)    check_configs ;;
    languages)  check_languages ;;
    docker)     check_docker ;;
    shell)      check_shell ;;
    *)
        echo -e "${RED}Unknown section: $SECTION${NC}" >&2
        echo "Valid: commands cli-tools configs languages docker shell all" >&2
        exit 1
        ;;
esac

# JSON output
if [[ "$OUTPUT_FORMAT" == "json" ]]; then
    echo "["
    first=true
    for f in "${JSON_FINDINGS[@]}"; do
        if $first; then first=false; else echo ","; fi
        echo -n "  $f"
    done
    echo ""
    echo "]"
fi

# Text summary
if [[ "$OUTPUT_FORMAT" == "text" ]]; then
    echo ""
    echo -e "${BLUE}============================================${NC}"
    gap=0 stale=0 drift=0 broken=0
    for f in "${FINDINGS[@]}"; do
        case "$f" in
            GAP) ((gap++)) || true ;;
            STALE) ((stale++)) || true ;;
            DRIFT) ((drift++)) || true ;;
            BROKEN) ((broken++)) || true ;;
        esac
    done
    echo -e " ${GREEN}[GAP]${NC}    $gap items on system but not in migration tools"
    echo -e " ${YELLOW}[DRIFT]${NC}  $drift items changed since migration tools were written"
    echo -e " ${RED}[STALE]${NC}  $stale items in migration tools but gone from system"
    echo -e " ${RED}[BROKEN]${NC} $broken broken symlinks or references"
    echo ""
    if (( gap + stale + drift + broken > 0 )); then
        echo -e " Run ${BLUE}/migration-check${NC} in Claude Code for AI analysis + fixes."
        exit 1
    else
        echo -e " ${GREEN}Migration tools are in sync with your system.${NC}"
    fi
fi
