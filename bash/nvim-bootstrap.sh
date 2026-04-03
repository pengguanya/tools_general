#!/bin/bash
#
# Script Name: nvim-bootstrap.sh
# Description: Full Neovim setup on a new machine (AppImage + plugins + LSP + treesitter)
# Usage: nvim-bootstrap [--check | --install] [-h]
# Requirements: curl, git, make, gcc (for treesitter/telescope-fzf-native compilation)
# Example: nvim-bootstrap --check
#          nvim-bootstrap --install
#

set -euo pipefail

NVIM_CONFIG="$HOME/.config/nvim"
NVIM_BIN="$HOME/.local/bin/nvim"
TIMEOUT_SEC=120

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

show_help() {
  cat << 'EOF'
Usage: nvim-bootstrap [OPTIONS]

Set up Neovim on a new machine: install AppImage binary, plugins, LSP servers, and treesitter parsers.

Prerequisites:
  - yadm submodules initialized (~/.config/nvim must exist)
  - curl, git, make, gcc available

Options:
  --check         Report what would be installed (default, dry-run)
  --install       Perform the full installation
  -h, --help      Show this help message
EOF
}

FAILED=0

check_prereq() {
  local cmd="$1"
  local desc="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    echo -e "${GREEN}  FOUND${NC} $cmd ($desc)"
    return 0
  else
    echo -e "${RED}  MISSING${NC} $cmd ($desc)"
    FAILED=$((FAILED + 1))
    return 1
  fi
}

do_check() {
  echo -e "${BLUE}=== Prerequisites ===${NC}"
  check_prereq curl "downloading AppImage"
  check_prereq git "version control"
  check_prereq make "compiling telescope-fzf-native"
  check_prereq gcc "compiling treesitter parsers"

  echo ""
  echo -e "${BLUE}=== tree-sitter CLI ===${NC}"
  if command -v tree-sitter >/dev/null 2>&1; then
    local ts_ver min_ver="0.26.1"
    ts_ver="$(tree-sitter --version 2>/dev/null | grep -oP '[\d.]+' | head -1)"
    if printf '%s\n%s' "$min_ver" "$ts_ver" | sort -V | head -1 | grep -q "^${min_ver}$"; then
      echo -e "${GREEN}  FOUND${NC} tree-sitter v$ts_ver"
    else
      echo -e "${RED}  OUTDATED${NC} tree-sitter v$ts_ver (need >= $min_ver)"
      echo -e "${YELLOW}  Update with: cargo install tree-sitter-cli or npm install -g tree-sitter-cli@latest${NC}"
      FAILED=$((FAILED + 1))
    fi
  else
    echo -e "${RED}  MISSING${NC} tree-sitter CLI (needed for parser compilation)"
    echo -e "${YELLOW}  Install with: cargo install tree-sitter-cli or npm install -g tree-sitter-cli@latest${NC}"
    FAILED=$((FAILED + 1))
  fi

  echo ""
  echo -e "${BLUE}=== Neovim Config ===${NC}"
  if [[ -f "$NVIM_CONFIG/init.lua" ]]; then
    echo -e "${GREEN}  FOUND${NC} $NVIM_CONFIG/init.lua"
  else
    echo -e "${RED}  MISSING${NC} $NVIM_CONFIG/init.lua"
    echo -e "${YELLOW}  Run: yadm submodule update --init --recursive${NC}"
    FAILED=$((FAILED + 1))
  fi

  echo ""
  echo -e "${BLUE}=== Neovim Binary ===${NC}"
  if [[ -x "$NVIM_BIN" ]]; then
    local version
    version="$("$NVIM_BIN" --version 2>/dev/null | head -1)"
    echo -e "${GREEN}  INSTALLED${NC} $version"
  else
    echo -e "${YELLOW}  NOT INSTALLED${NC} (will be installed via nvim-update)"
  fi

  echo ""
  echo -e "${BLUE}=== Plugin Data ===${NC}"
  local lazy_dir="$HOME/.local/share/nvim/lazy"
  if [[ -d "$lazy_dir" ]]; then
    local count
    count="$(ls -1d "$lazy_dir"/*/ 2>/dev/null | wc -l)"
    echo -e "${GREEN}  FOUND${NC} $count plugins in $lazy_dir"
  else
    echo -e "${YELLOW}  NOT INSTALLED${NC} (will be installed via :Lazy sync)"
  fi

  echo ""
  echo -e "${BLUE}=== Mason Tools ===${NC}"
  local mason_bin="$HOME/.local/share/nvim/mason/bin"
  if [[ -d "$mason_bin" ]]; then
    local count
    count="$(ls -1 "$mason_bin" 2>/dev/null | wc -l)"
    echo -e "${GREEN}  FOUND${NC} $count tools in $mason_bin"
  else
    echo -e "${YELLOW}  NOT INSTALLED${NC} (will be installed via :MasonToolsInstallSync)"
  fi

  echo ""
  if (( FAILED > 0 )); then
    echo -e "${RED}$FAILED prerequisite(s) missing. Fix before running --install.${NC}"
    exit 1
  else
    echo -e "${GREEN}Ready for installation. Run: nvim-bootstrap --install${NC}"
  fi
}

do_install() {
  echo -e "${BLUE}=== Neovim Bootstrap ===${NC}"
  echo ""

  # Step 1: Check prerequisites
  echo -e "${BLUE}Step 1: Checking prerequisites...${NC}"
  local missing=false
  for cmd in curl git make gcc; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo -e "${RED}  Missing: $cmd${NC}"
      missing=true
    fi
  done
  if [[ "$missing" == true ]]; then
    echo -e "${RED}Install missing prerequisites first.${NC}" >&2
    exit 1
  fi
  echo -e "${GREEN}  All prerequisites found.${NC}"
  echo ""

  # Step 2: Verify config
  echo -e "${BLUE}Step 2: Verifying nvim config...${NC}"
  if [[ ! -f "$NVIM_CONFIG/init.lua" ]]; then
    echo -e "${RED}  Config not found at $NVIM_CONFIG/init.lua${NC}" >&2
    echo -e "${YELLOW}  Run: yadm submodule update --init --recursive${NC}" >&2
    exit 1
  fi
  echo -e "${GREEN}  Config found at $NVIM_CONFIG${NC}"
  echo ""

  # Step 3: Install neovim binary
  echo -e "${BLUE}Step 3: Installing Neovim binary...${NC}"
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -x "$script_dir/nvim-update.sh" ]]; then
    bash "$script_dir/nvim-update.sh" --install
  elif command -v nvim-update >/dev/null 2>&1; then
    nvim-update --install
  else
    echo -e "${RED}  nvim-update not found. Run setup_symlinks first.${NC}" >&2
    exit 1
  fi
  echo ""

  # Step 4: Install plugins
  echo -e "${BLUE}Step 4: Installing plugins via lazy.nvim...${NC}"
  if timeout "$TIMEOUT_SEC" "$NVIM_BIN" --headless "+Lazy! sync" "+qa" 2>&1; then
    echo -e "${GREEN}  Plugins installed.${NC}"
  else
    echo -e "${YELLOW}  Plugin installation may have timed out or had errors. Launch nvim manually to verify.${NC}"
  fi
  echo ""

  # Step 5: Install Mason tools
  echo -e "${BLUE}Step 5: Installing Mason tools (LSP servers, formatters)...${NC}"
  if timeout "$TIMEOUT_SEC" "$NVIM_BIN" --headless "+MasonToolsInstallSync" "+qa" 2>&1; then
    echo -e "${GREEN}  Mason tools installed.${NC}"
  else
    echo -e "${YELLOW}  Mason installation may have timed out. Open :Mason in nvim to verify.${NC}"
  fi
  echo ""

  # Step 6: Install treesitter parsers
  echo -e "${BLUE}Step 6: Installing treesitter parsers...${NC}"
  if ! command -v tree-sitter >/dev/null 2>&1; then
    echo -e "${YELLOW}  tree-sitter CLI not found -- parsers requiring compilation will be skipped.${NC}"
    echo -e "${YELLOW}  Install with: cargo install tree-sitter-cli or npm install -g tree-sitter-cli@latest${NC}"
  else
    local ts_ver min_ver="0.26.1"
    ts_ver="$(tree-sitter --version 2>/dev/null | grep -oP '[\d.]+' | head -1)"
    if ! printf '%s\n%s' "$min_ver" "$ts_ver" | sort -V | head -1 | grep -q "^${min_ver}$"; then
      echo -e "${YELLOW}  tree-sitter CLI v${ts_ver} is too old (need >= ${min_ver}).${NC}"
      echo -e "${YELLOW}  Update with: cargo install tree-sitter-cli or npm install -g tree-sitter-cli@latest${NC}"
    fi
  fi
  if timeout "$TIMEOUT_SEC" "$NVIM_BIN" --headless -c "TSUpdate" -c "sleep 20" -c "qa!" 2>&1; then
    echo -e "${GREEN}  Treesitter parsers installed.${NC}"
  else
    echo -e "${YELLOW}  Treesitter installation may have timed out. Parsers will install on first use.${NC}"
  fi
  echo ""

  # Step 7: Health check
  echo -e "${BLUE}Step 7: Running health check...${NC}"
  if [[ -x "$script_dir/nvim-health.sh" ]]; then
    bash "$script_dir/nvim-health.sh" --all || true
  elif command -v nvim-health >/dev/null 2>&1; then
    nvim-health --all || true
  else
    echo -e "${YELLOW}  nvim-health not available. Run :checkhealth in nvim.${NC}"
  fi

  echo ""
  echo -e "${GREEN}=== Bootstrap Complete ===${NC}"
}

# --- Main ---

action="check"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)   action="check"; shift ;;
    --install) action="install"; shift ;;
    -h|--help) show_help; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      show_help >&2
      exit 1 ;;
  esac
done

case "$action" in
  check)   do_check ;;
  install) do_install ;;
esac
