#!/bin/bash
#
# Script Name: nvim-maintain.sh
# Description: Orchestrator for Neovim maintenance (update, sync, health, plugins, mason, treesitter)
# Usage: nvim-maintain [--check | --update | --full | --plugins | --mason | --treesitter] [-h]
# Requirements: nvim, curl, git
# Example: nvim-maintain --check
#          nvim-maintain --update
#          nvim-maintain --full
#

set -euo pipefail

NVIM_BIN="${NVIM_BIN:-$HOME/.local/bin/nvim}"
TIMEOUT_SEC=120

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

show_help() {
  cat << 'EOF'
Usage: nvim-maintain [OPTIONS]

Neovim maintenance orchestrator.

Options:
  --check         Status report only (default): version, upstream, health
  --update        Update binary (AppImage) + health check
  --full          Update binary + sync upstream + health check
  --plugins       Update lazy.nvim plugins + health check
  --mason         Update Mason tools + health check
  --treesitter    Update treesitter parsers + health check
  -h, --help      Show this help message

This script composes: nvim-update, nvim-sync-upstream, nvim-health.
EOF
}

# Resolve companion scripts -- try same directory first, then PATH
find_script() {
  local name="$1"
  local script_dir
  script_dir="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

  if [[ -x "$script_dir/${name}.sh" ]]; then
    echo "$script_dir/${name}.sh"
  elif command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
  else
    echo ""
  fi
}

run_script() {
  local name="$1"
  shift
  local script_path
  script_path="$(find_script "$name")"

  if [[ -z "$script_path" ]]; then
    echo -e "${RED}Error: $name not found. Run setup_symlinks.${NC}" >&2
    return 1
  fi

  bash "$script_path" "$@"
}

section() {
  echo ""
  echo -e "${BLUE}════════════════════════════════════════${NC}"
  echo -e "${BLUE}  $1${NC}"
  echo -e "${BLUE}════════════════════════════════════════${NC}"
}

do_check() {
  section "Neovim Version Status"
  run_script nvim-update --check || true

  section "Upstream Fork Status"
  run_script nvim-sync-upstream --check || true

  section "Health Check"
  run_script nvim-health --all || true
}

do_update() {
  section "Updating Neovim Binary"
  run_script nvim-update --install

  section "Health Check"
  run_script nvim-health --all || true
}

do_full() {
  section "Updating Neovim Binary"
  run_script nvim-update --install

  section "Syncing Upstream Kickstart"
  run_script nvim-sync-upstream --merge --stash || {
    local exit_code=$?
    if (( exit_code == 2 )); then
      echo -e "${YELLOW}Merge conflicts detected. Resolve manually, then re-run health check.${NC}"
    fi
  }

  section "Health Check"
  run_script nvim-health --all || true
}

do_plugins() {
  section "Updating Plugins"
  if timeout "$TIMEOUT_SEC" "$NVIM_BIN" --headless "+Lazy! sync" "+qa" 2>&1; then
    echo -e "${GREEN}Plugin update complete.${NC}"
  else
    echo -e "${YELLOW}Plugin update may have timed out. Check in nvim with :Lazy${NC}"
  fi

  section "Health Check"
  run_script nvim-health --startup --plugins || true
}

do_mason() {
  section "Updating Mason Tools"
  if timeout "$TIMEOUT_SEC" "$NVIM_BIN" --headless "+MasonToolsInstallSync" "+qa" 2>&1; then
    echo -e "${GREEN}Mason update complete.${NC}"
  else
    echo -e "${YELLOW}Mason update may have timed out. Check in nvim with :Mason${NC}"
  fi

  section "Health Check"
  run_script nvim-health --startup --lsp || true
}

do_treesitter() {
  # Pre-flight: verify tree-sitter CLI is available and compatible
  section "Checking tree-sitter CLI"
  if ! command -v tree-sitter >/dev/null 2>&1; then
    echo -e "${RED}Error: tree-sitter CLI not found in PATH.${NC}"
    echo -e "${YELLOW}Install with: cargo install tree-sitter-cli or npm install -g tree-sitter-cli@latest${NC}"
    return 1
  fi

  local ts_version min_version="0.26.1"
  ts_version="$(tree-sitter --version 2>/dev/null | grep -oP '[\d.]+' | head -1)"
  if ! printf '%s\n%s' "$min_version" "$ts_version" | sort -V | head -1 | grep -q "^${min_version}$"; then
    echo -e "${RED}Error: tree-sitter CLI v${ts_version} is too old (need >= ${min_version}).${NC}"
    echo -e "${YELLOW}Update with: cargo install tree-sitter-cli or npm install -g tree-sitter-cli@latest${NC}"
    return 1
  fi
  echo -e "${GREEN}tree-sitter CLI: v${ts_version}${NC}"

  section "Updating Treesitter Parsers"
  local ts_output
  ts_output="$(timeout "$TIMEOUT_SEC" "$NVIM_BIN" --headless \
    -c "TSUpdate" -c "sleep 20" -c "qa!" 2>&1)" || true

  # Check for real errors (ABI mismatch, compilation failures), excluding routine messages
  local ts_errors
  ts_errors="$(echo "$ts_output" | grep -iE 'error|panic|failed' \
    | grep -viE 'up-to-date|successfully' || true)"

  if [[ -n "$ts_errors" ]]; then
    echo -e "${RED}Treesitter update encountered errors:${NC}"
    echo "$ts_errors"
    echo ""
    echo -e "${YELLOW}Some parsers may have failed to compile. Run nvim-health --treesitter for details.${NC}"
  else
    echo -e "${GREEN}Treesitter update complete.${NC}"
  fi

  section "Health Check"
  run_script nvim-health --startup --treesitter || true
}

# --- Main ---

action="check"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)      action="check"; shift ;;
    --update)     action="update"; shift ;;
    --full)       action="full"; shift ;;
    --plugins)    action="plugins"; shift ;;
    --mason)      action="mason"; shift ;;
    --treesitter) action="treesitter"; shift ;;
    -h|--help)    show_help; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      show_help >&2
      exit 1 ;;
  esac
done

echo -e "${BLUE}Neovim Maintenance${NC} ($(date +%Y-%m-%d\ %H:%M))"

case "$action" in
  check)      do_check ;;
  update)     do_update ;;
  full)       do_full ;;
  plugins)    do_plugins ;;
  mason)      do_mason ;;
  treesitter) do_treesitter ;;
esac

echo ""
echo -e "${GREEN}Done.${NC}"
