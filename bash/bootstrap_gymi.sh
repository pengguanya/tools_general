#!/usr/bin/env bash
#
# Script Name: bootstrap_gymi.sh
# Description: Reproduce the Gymiprufung batch training workflow on a fresh machine
# Usage: bootstrap_gymi.sh [--check | -h]
# Requirements: git, curl, sudo (for apt)
# Example: cd ~/tools/general && bash bash/bootstrap_gymi.sh
#          bash bash/bootstrap_gymi.sh --check
#
set -euo pipefail

# ============================================================
# Configuration — edit here when adding packages, repos, etc.
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# Git repos
AICONF_GIT="$HOME/.ai-config.git"
AICONF_REMOTE="git@github.com:pengguanya/ai-config.git"
STUDY_DIR="$HOME/work/luca_study"
STUDY_REMOTE="git@github.com:pengguanya/luca_study.git"

# System packages (apt)
APT_PACKAGES=(
    texlive-xetex           # XeLaTeX engine
    texlive-latex-extra     # tcolorbox, tikz, multicol, booktabs, etc.
    texlive-fonts-recommended
    texlive-lang-german     # German hyphenation (polyglossia)
    fonts-liberation        # Liberation Sans (used by LaTeX preamble)
    fonts-dejavu            # DejaVu Sans Mono (used by LaTeX preamble)
    poppler-utils           # pdfunite for combining PDFs
    jq                      # JSON parsing in shell scripts
    python3                 # Python scripts
    python3-pip             # pip for installing Python packages
)

# Python packages: "import_check:pip_name"
PY_MODULES=(
    "jinja2:jinja2"
    "pypdf:pypdf"
)

# ============================================================
# Output helpers
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}[done]${NC} $1"; }
skip() { echo -e "  ${YELLOW}[skip]${NC} $1 (already set up)"; }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; }

PHASE=0
phase() { PHASE=$((PHASE + 1)); echo -e "\n${BOLD}${BLUE}=== Phase $PHASE: $1 ===${NC}"; }

ERRORS=0
CHECKS=0
PASSED=0

# Verification helpers — no eval needed
verify_cmd() {
    local label="$1"; shift
    CHECKS=$((CHECKS + 1))
    if "$@" &>/dev/null; then
        ok "$label"
        PASSED=$((PASSED + 1))
    else
        fail "$label"
        ERRORS=$((ERRORS + 1))
    fi
}

verify_path() {
    local label="$1" path="$2"
    CHECKS=$((CHECKS + 1))
    if [[ -e "$path" ]]; then
        ok "$label"
        PASSED=$((PASSED + 1))
    else
        fail "$label"
        ERRORS=$((ERRORS + 1))
    fi
}

verify_import() {
    local label="$1" module="$2"
    CHECKS=$((CHECKS + 1))
    if python3 -c "import $module" &>/dev/null; then
        ok "$label"
        PASSED=$((PASSED + 1))
    else
        fail "$label"
        ERRORS=$((ERRORS + 1))
    fi
}

# ============================================================
# Argument parsing
# ============================================================

show_help() {
    cat << 'EOF'
Usage: bootstrap_gymi.sh [OPTIONS]

Set up the Gymiprufung batch training workflow: install system packages,
Python dependencies, CLI symlinks, aiconf skills, and student data repos.

Idempotent: safe to re-run. Each step checks if already done.
Does NOT install Claude Code, set up SSH keys, or touch secrets.

Options:
  --check       Report what is set up and what is missing (no changes)
  -h, --help    Show this help message

Quick start (fresh WSL2 Ubuntu machine with git + Claude Code):
  git clone git@github.com:pengguanya/tools_general.git ~/tools/general
  cd ~/tools/general && bash bash/bootstrap_gymi.sh
EOF
}

MODE="install"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check)    MODE="check"; shift ;;
        -h|--help)  show_help; exit 0 ;;
        *)
            echo "Unknown option: $1" >&2
            show_help >&2
            exit 1 ;;
    esac
done

# ============================================================
# Verification phase (used by both --check and full run)
# ============================================================

run_verification() {
    phase "Verification"

    verify_cmd  "uv"                                command -v uv
    verify_cmd  "xelatex"                           command -v xelatex
    verify_cmd  "pdfunite"                           command -v pdfunite
    verify_cmd  "jq"                                command -v jq
    verify_cmd  "python3"                           command -v python3

    for entry in "${PY_MODULES[@]}"; do
        local mod="${entry%%:*}"
        verify_import "$mod (python)" "$mod"
    done

    verify_cmd  "Claude Code"                       command -v claude
    verify_cmd  "mathe-ueben (symlink)"             command -v mathe-ueben

    verify_path "deutsch-batch-training skill"      "$HOME/.claude/skills/deutsch-batch-training/SKILL.md"
    verify_path "math-batch-training skill"         "$HOME/.claude/skills/math-batch-training/SKILL.md"
    verify_path "shared library"                    "$HOME/.claude/skills/shared/lib/config_base.sh"
    verify_path "render engine"                     "$HOME/.claude/skills/shared/templates/render_base.py"
    verify_path "LaTeX preamble"                    "$HOME/.claude/skills/shared/templates/preamble.tex"
    verify_path "luca_study/config.json"            "$STUDY_DIR/config.json"
    verify_path "deutsch student profile"           "$STUDY_DIR/deutsch/student_profile.json"
    verify_path "math student profile"              "$STUDY_DIR/math/student_profile.json"
    verify_path "Gymiprufung submodule"             "$STUDY_DIR/Gymiprufung/.git"
}

# ============================================================
# Check-only mode: skip installation, jump to verification
# ============================================================

if [[ "$MODE" == "check" ]]; then
    echo -e "${BOLD}Running in check-only mode (no changes will be made)${NC}"
    run_verification

    echo ""
    echo -e "${BOLD}=== Summary ===${NC}"
    echo -e "  Checks: ${PASSED}/${CHECKS} passed"

    if [[ $ERRORS -eq 0 ]]; then
        echo -e "  ${GREEN}${BOLD}All good.${NC}"
    else
        echo -e "  ${RED}${BOLD}${ERRORS} issue(s) found.${NC} Run without --check to install."
    fi

    exit $(( ERRORS > 0 ? 1 : 0 ))
fi

# ============================================================
# Phase: System packages
# ============================================================
phase "System packages (apt)"

MISSING_PKGS=()
for pkg in "${APT_PACKAGES[@]}"; do
    if ! dpkg -s "$pkg" &>/dev/null; then
        MISSING_PKGS+=("$pkg")
    fi
done

if [[ ${#MISSING_PKGS[@]} -gt 0 ]]; then
    echo "  Installing ${#MISSING_PKGS[@]} packages (needs sudo)..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq "${MISSING_PKGS[@]}"
    ok "Installed: ${MISSING_PKGS[*]}"
else
    skip "All ${#APT_PACKAGES[@]} packages"
fi

# ============================================================
# Phase: uv (Python package manager)
# ============================================================
phase "uv (Python package manager)"

if command -v uv &>/dev/null; then
    skip "uv $(uv --version 2>/dev/null | awk '{print $2}')"
else
    echo "  Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
    ok "uv $(uv --version 2>/dev/null | awk '{print $2}')"
fi

# ============================================================
# Phase: Python packages
# ============================================================
phase "Python packages (uv)"

PIP_NEEDED=()
for entry in "${PY_MODULES[@]}"; do
    mod="${entry%%:*}"
    pkg="${entry##*:}"
    if ! python3 -c "import $mod" &>/dev/null; then
        PIP_NEEDED+=("$pkg")
    fi
done

if [[ ${#PIP_NEEDED[@]} -gt 0 ]]; then
    # --break-system-packages: bypass PEP 668 externally-managed check on newer Ubuntu
    # --target user-site: install to ~/.local/lib without requiring sudo
    uv pip install \
        --python "$(command -v python3)" \
        --break-system-packages \
        --target "$(python3 -c 'import site; print(site.getusersitepackages())')" \
        --quiet \
        "${PIP_NEEDED[@]}"
    ok "Installed: ${PIP_NEEDED[*]}"
else
    names=()
    for entry in "${PY_MODULES[@]}"; do names+=("${entry%%:*}"); done
    skip "${names[*]}"
fi

# ============================================================
# Phase: Shell setup
# ============================================================
phase "Shell setup (PATH, aliases)"

# Detect shell rc file
if [[ -n "${ZSH_VERSION:-}" ]] || [[ "$SHELL" == */zsh ]]; then
    SHELL_RC="$HOME/.zshrc"
else
    SHELL_RC="$HOME/.bashrc"
fi

# Ensure ~/.local/bin in PATH
mkdir -p "$HOME/.local/bin"
if ! grep -q '\.local/bin' "$SHELL_RC" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_RC"
    ok "Added ~/.local/bin to PATH in $SHELL_RC"
else
    skip "~/.local/bin in PATH"
fi

# Ensure aiconf alias
if ! grep -q 'alias aiconf=' "$SHELL_RC" 2>/dev/null && \
   ! grep -q 'alias aiconf=' "$HOME/.bash_aliases" 2>/dev/null; then
    echo "alias aiconf='git --git-dir=\$HOME/.ai-config.git --work-tree=\$HOME'" >> "$SHELL_RC"
    ok "Added aiconf alias to $SHELL_RC"
else
    skip "aiconf alias"
fi

# Source updates for this session
export PATH="$HOME/.local/bin:$PATH"

# ============================================================
# Phase: CLI tool symlinks
# ============================================================
phase "CLI tool symlinks (setup_symlinks.sh)"

if [[ -f "$SCRIPT_DIR/setup_symlinks.sh" ]]; then
    bash "$SCRIPT_DIR/setup_symlinks.sh"
    ok "Symlinks created (mathe-ueben, mathe-block, sync-ai-skills, ...)"
else
    fail "setup_symlinks.sh not found in $SCRIPT_DIR"
    ERRORS=$((ERRORS + 1))
fi

# ============================================================
# Phase: aiconf (skills, shared libs, agents)
# ============================================================
phase "aiconf (Claude skills + shared libraries)"

if [[ -d "$AICONF_GIT" ]]; then
    echo "  Pulling latest skills..."
    if git --git-dir="$AICONF_GIT" --work-tree="$HOME" pull --rebase origin main 2>/dev/null; then
        ok "aiconf updated"
    else
        fail "aiconf pull failed (conflicts or network issue)"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo "  Cloning aiconf (bare repo)..."
    git clone --bare "$AICONF_REMOTE" "$AICONF_GIT"
    git --git-dir="$AICONF_GIT" --work-tree="$HOME" config status.showUntrackedFiles no
    git --git-dir="$AICONF_GIT" --work-tree="$HOME" config core.excludesFile "$HOME/.ai-config.gitignore"

    if ! git --git-dir="$AICONF_GIT" --work-tree="$HOME" checkout 2>/dev/null; then
        echo "  Backing up conflicting files..."
        mkdir -p "$HOME/.ai-config-backup"
        git --git-dir="$AICONF_GIT" --work-tree="$HOME" checkout 2>&1 \
            | grep -oP '^\t\K.*' \
            | while read -r f; do
                mkdir -p "$HOME/.ai-config-backup/$(dirname "$f")"
                cp "$HOME/$f" "$HOME/.ai-config-backup/$f" 2>/dev/null || true
            done
        git --git-dir="$AICONF_GIT" --work-tree="$HOME" checkout -f
        echo "  Backups in ~/.ai-config-backup/ — review if needed."
    fi

    ok "Skills restored: deutsch-batch-training, math-batch-training, shared/, ..."
fi

# ============================================================
# Phase: luca_study (student data + exams)
# ============================================================
phase "luca_study (student data, worksheets, exams)"

if [[ -d "$STUDY_DIR/.git" ]]; then
    echo "  Pulling latest study content..."
    if git -C "$STUDY_DIR" pull --rebase origin main 2>/dev/null; then
        git -C "$STUDY_DIR" submodule update --init --recursive 2>/dev/null
        ok "luca_study updated"
    else
        fail "luca_study pull failed (conflicts or network issue)"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo "  Cloning luca_study (with Gymiprufung submodule)..."
    mkdir -p "$HOME/work"
    git clone --recurse-submodules "$STUDY_REMOTE" "$STUDY_DIR"
    ok "Cloned luca_study + Gymiprufung submodule"
fi

# ============================================================
# Phase: Verification
# ============================================================
run_verification

# ============================================================
# Summary
# ============================================================
echo ""
echo -e "${BOLD}=== Summary ===${NC}"
echo -e "  Checks: ${PASSED}/${CHECKS} passed"

if [[ $ERRORS -eq 0 ]]; then
    echo -e "  ${GREEN}${BOLD}All good.${NC} Ready to use."
    echo ""
    echo "  Next steps:"
    echo "    cd ~/work/luca_study"
    echo "    claude"
    echo "    # then: /deutsch-batch-training status"
    echo "    # then: /math-batch-training status"
else
    echo -e "  ${RED}${BOLD}${ERRORS} issue(s) found.${NC} Check output above."
    echo "  Re-run this script after fixing to verify."
fi

echo ""
echo "  Repos:"
echo "    Skills/agents:  aiconf  (pengguanya/ai-config)"
echo "    CLI tools:      ~/tools/general  (pengguanya/tools_general)"
echo "    Student data:   ~/work/luca_study  (pengguanya/luca_study)"
echo "    Past exams:     ~/work/luca_study/Gymiprufung  (submodule)"

exit $(( ERRORS > 0 ? 1 : 0 ))
