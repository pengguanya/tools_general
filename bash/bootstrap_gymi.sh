#!/usr/bin/env bash
set -euo pipefail

# bootstrap_gymi.sh — Reproduce the Gymiprufung batch training workflow
#
# Usage (on a fresh WSL2 Ubuntu machine with git + Claude Code):
#   git clone git@github.com:pengguanya/tools_general.git ~/tools/general
#   cd ~/tools/general && bash bash/bootstrap_gymi.sh
#
# Idempotent: safe to re-run. Each step checks if already done.
# Does NOT install Claude Code, set up SSH keys, or touch secrets.

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}[done]${NC} $1"; }
skip() { echo -e "  ${YELLOW}[skip]${NC} $1 (already set up)"; }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; }
phase() { echo -e "\n${BOLD}${BLUE}=== Phase $1: $2 ===${NC}"; }

ERRORS=0

# ============================================================
# Phase 1: System packages
# ============================================================
phase 1 "System packages (apt)"

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
# Phase 2: uv (Python package manager)
# ============================================================
phase 2 "uv (Python package manager)"

if command -v uv &>/dev/null; then
    skip "uv $(uv --version 2>/dev/null | awk '{print $2}')"
else
    echo "  Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
    ok "uv $(uv --version 2>/dev/null | awk '{print $2}')"
fi

# ============================================================
# Phase 3: Python packages
# ============================================================
phase 3 "Python packages (uv)"

PIP_NEEDED=()
if ! python3 -c "import jinja2" &>/dev/null; then
    PIP_NEEDED+=(jinja2)
fi
if ! python3 -c "from pypdf import PdfWriter" &>/dev/null; then
    PIP_NEEDED+=(pypdf)
fi

if [[ ${#PIP_NEEDED[@]} -gt 0 ]]; then
    uv pip install --python "$(command -v python3)" --break-system-packages --target "$(python3 -c 'import site; print(site.getusersitepackages())')" --quiet "${PIP_NEEDED[@]}"
    ok "Installed: ${PIP_NEEDED[*]}"
else
    skip "jinja2, pypdf"
fi

# ============================================================
# Phase 4: Shell setup
# ============================================================
phase 4 "Shell setup (PATH, aliases)"

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
# Phase 5: CLI tool symlinks
# ============================================================
phase 5 "CLI tool symlinks (setup_symlinks.sh)"

if [[ -f "$SCRIPT_DIR/setup_symlinks.sh" ]]; then
    bash "$SCRIPT_DIR/setup_symlinks.sh" 2>/dev/null
    ok "Symlinks created (mathe-ueben, mathe-block, sync-ai-skills, ...)"
else
    fail "setup_symlinks.sh not found in $SCRIPT_DIR"
    ((ERRORS++))
fi

# ============================================================
# Phase 6: aiconf (skills, shared libs, agents)
# ============================================================
phase 6 "aiconf (Claude skills + shared libraries)"

AICONF_GIT="$HOME/.ai-config.git"
AICONF_REMOTE="git@github.com:pengguanya/ai-config.git"

if [[ -d "$AICONF_GIT" ]]; then
    skip "aiconf repo ($AICONF_GIT exists)"
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
# Phase 7: luca_study (student data + exams)
# ============================================================
phase 7 "luca_study (student data, worksheets, exams)"

STUDY_DIR="$HOME/work/luca_study"
STUDY_REMOTE="git@github.com:pengguanya/luca_study.git"

if [[ -d "$STUDY_DIR/.git" ]]; then
    skip "luca_study ($STUDY_DIR exists)"
else
    echo "  Cloning luca_study (with Gymiprufung submodule)..."
    mkdir -p "$HOME/work"
    git clone --recurse-submodules "$STUDY_REMOTE" "$STUDY_DIR"
    ok "Cloned luca_study + Gymiprufung submodule"
fi

# ============================================================
# Phase 8: Verification
# ============================================================
phase 8 "Verification"

CHECKS=0
PASSED=0

verify() {
    ((CHECKS++))
    if eval "$1" &>/dev/null; then
        ok "$2"
        ((PASSED++))
    else
        fail "$2"
        ((ERRORS++))
    fi
}

verify "command -v uv"                               "uv"
verify "command -v xelatex"                          "xelatex"
verify "command -v pdfunite"                         "pdfunite"
verify "command -v jq"                               "jq"
verify "command -v python3"                          "python3"
verify "python3 -c 'import jinja2'"                  "jinja2 (python)"
verify "python3 -c 'from pypdf import PdfWriter'"    "pypdf (python)"
verify "command -v claude"                           "Claude Code"
verify "command -v mathe-ueben"                      "mathe-ueben (symlink)"
verify "[[ -f $HOME/.claude/skills/deutsch-batch-training/SKILL.md ]]" \
                                                     "deutsch-batch-training skill"
verify "[[ -f $HOME/.claude/skills/math-batch-training/SKILL.md ]]" \
                                                     "math-batch-training skill"
verify "[[ -f $HOME/.claude/skills/shared/lib/config_base.sh ]]" \
                                                     "shared library"
verify "[[ -f $HOME/.claude/skills/shared/templates/render_base.py ]]" \
                                                     "render engine"
verify "[[ -f $HOME/.claude/skills/shared/templates/preamble.tex ]]" \
                                                     "LaTeX preamble"
verify "[[ -f $STUDY_DIR/config.json ]]"             "luca_study/config.json"
verify "[[ -f $STUDY_DIR/deutsch/student_profile.json ]]" \
                                                     "deutsch student profile"
verify "[[ -f $STUDY_DIR/math/student_profile.json ]]" \
                                                     "math student profile"
verify "[[ -e $STUDY_DIR/Gymiprufung/.git ]]"        "Gymiprufung submodule"

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
