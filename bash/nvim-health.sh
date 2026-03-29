#!/bin/bash
#
# Script Name: nvim-health.sh
# Description: Run health checks on Neovim installation (binary, plugins, LSP, treesitter)
# Usage: nvim-health [--all | --binary | --plugins | --lsp | --treesitter] [-q] [-h]
# Requirements: nvim
# Example: nvim-health --all
#          nvim-health --plugins --lsp
#

set -euo pipefail

NVIM_BIN="${NVIM_BIN:-$HOME/.local/bin/nvim}"
NVIM_CONFIG="$HOME/.config/nvim"
TIMEOUT_SEC=60

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

QUIET=false
FAILED=0

show_help() {
  cat << 'EOF'
Usage: nvim-health [OPTIONS]

Run health checks on Neovim installation.

Options:
  --all             Run all checks (default)
  --binary          Check binary version
  --startup         Check for errors/warnings on startup
  --plugins         Check lazy.nvim plugin status
  --lsp             Check Mason-installed LSP servers
  --treesitter      Check treesitter parsers
  -q, --quiet       Exit code only, no output
  -h, --help        Show this help message

Exit codes:
  0  All checks passed
  1  One or more checks failed
EOF
}

log() {
  if [[ "$QUIET" == false ]]; then
    echo -e "$@"
  fi
}

pass() { log "${GREEN}  PASS${NC} $1"; }
fail() { log "${RED}  FAIL${NC} $1"; FAILED=$((FAILED + 1)); }
info() { log "${BLUE}  INFO${NC} $1"; }

check_binary() {
  log ""
  log "${BLUE}=== Binary ===${NC}"

  if [[ ! -f "$NVIM_BIN" ]]; then
    fail "nvim not found at $NVIM_BIN"
    return
  fi

  if [[ ! -x "$NVIM_BIN" ]]; then
    fail "nvim not executable at $NVIM_BIN"
    return
  fi

  local version
  version="$(timeout "$TIMEOUT_SEC" "$NVIM_BIN" --version 2>/dev/null | head -1)" || {
    fail "nvim --version failed or timed out"
    return
  }

  pass "Binary: $version"

  local file_type
  file_type="$(file "$NVIM_BIN" 2>/dev/null | head -1)"
  if echo "$file_type" | grep -qi "appimage\|ISO 9660\|ELF"; then
    info "Type: $(echo "$file_type" | sed "s|$NVIM_BIN: ||")"
  elif echo "$file_type" | grep -qi "script\|text"; then
    info "Type: wrapper script (extracted AppImage)"
  fi
}

check_startup() {
  log ""
  log "${BLUE}=== Startup ===${NC}"

  if [[ ! -x "$NVIM_BIN" ]]; then
    fail "nvim not available"
    return
  fi

  # Launch nvim headless, wait for plugins to load, then capture :messages.
  # vim.notify warnings don't appear on stderr in headless mode, but they
  # do appear in the message log accessible via :messages.
  # We write messages to a temp file to avoid output interleaving issues.
  local msgfile
  msgfile="$(mktemp)"
  trap "rm -f '$msgfile'" RETURN

  local output
  output="$(timeout "$TIMEOUT_SEC" "$NVIM_BIN" --headless \
    "+lua vim.defer_fn(function() local f = io.open('$msgfile', 'w'); local m = vim.api.nvim_exec2('messages', {output=true}).output; if f then f:write(m); f:close() end; vim.cmd('qa!') end, 2000)" \
    2>&1)" || true

  local messages
  messages="$(cat "$msgfile" 2>/dev/null)" || true

  # Check messages for warnings/errors from plugins
  local msg_errors
  msg_errors="$(echo "$messages" | grep -iE 'error|has been removed|deprecated|failed to run' \
    | grep -v '^$' || true)"

  # Also check raw output for Lua errors (e.g., "Failed to run `config`")
  local lua_errors
  lua_errors="$(echo "$output" | grep -iE 'Failed to run|Error detected|stack traceback' || true)"

  local all_errors
  all_errors="$(printf '%s\n%s' "$msg_errors" "$lua_errors" | grep -v '^$' | sort -u || true)"

  if [[ -n "$all_errors" ]]; then
    fail "Startup errors/warnings detected:"
    echo "$all_errors" | while IFS= read -r line; do
      log "    $line"
    done
  else
    pass "No startup errors or warnings"
  fi
}

check_plugins() {
  log ""
  log "${BLUE}=== Plugins (lazy.nvim) ===${NC}"

  if [[ ! -x "$NVIM_BIN" ]]; then
    fail "nvim not available"
    return
  fi

  local output
  output="$(timeout "$TIMEOUT_SEC" "$NVIM_BIN" --headless \
    "+lua local ok, lazy = pcall(require, 'lazy'); if ok then local s = lazy.stats(); print('LAZY_STATS:' .. s.count .. ':' .. s.loaded) else print('LAZY_ERROR:not found') end" \
    "+qa" 2>&1)" || true

  if echo "$output" | grep -q "LAZY_ERROR"; then
    fail "lazy.nvim not found"
    return
  fi

  local stats_line
  stats_line="$(echo "$output" | grep "LAZY_STATS:" | head -1)"
  if [[ -n "$stats_line" ]]; then
    local count loaded
    count="$(echo "$stats_line" | cut -d: -f2)"
    loaded="$(echo "$stats_line" | cut -d: -f3)"
    pass "Plugins: $count total, $loaded loaded at startup"
  else
    fail "Could not read lazy.nvim stats"
  fi
}

check_lsp() {
  log ""
  log "${BLUE}=== LSP / Mason ===${NC}"

  if [[ ! -x "$NVIM_BIN" ]]; then
    fail "nvim not available"
    return
  fi

  local mason_dir="$HOME/.local/share/nvim/mason"
  if [[ ! -d "$mason_dir" ]]; then
    fail "Mason directory not found at $mason_dir"
    return
  fi

  # List installed Mason packages from the filesystem (more reliable than headless)
  local bin_dir="$mason_dir/bin"
  if [[ -d "$bin_dir" ]]; then
    local tools
    tools="$(ls -1 "$bin_dir" 2>/dev/null | sort)"
    if [[ -n "$tools" ]]; then
      local count
      count="$(echo "$tools" | wc -l)"
      pass "Mason tools installed: $count"
      echo "$tools" | while read -r tool; do
        info "  $tool"
      done
    else
      fail "No Mason tools installed"
    fi
  else
    fail "Mason bin directory not found"
  fi
}

check_treesitter() {
  log ""
  log "${BLUE}=== Treesitter ===${NC}"

  if [[ ! -x "$NVIM_BIN" ]]; then
    fail "nvim not available"
    return
  fi

  local parser_dir="$HOME/.local/share/nvim/lazy/nvim-treesitter/parser"
  if [[ ! -d "$parser_dir" ]]; then
    # Try alternate location
    parser_dir="$HOME/.local/share/nvim/site/parser"
  fi

  if [[ -d "$parser_dir" ]]; then
    local count
    count="$(ls -1 "$parser_dir"/*.so 2>/dev/null | wc -l)"
    if (( count > 0 )); then
      pass "Treesitter parsers installed: $count"
      # List a few key ones
      for lang in lua python bash r markdown json yaml; do
        if [[ -f "$parser_dir/${lang}.so" ]]; then
          info "  $lang"
        fi
      done
    else
      fail "No treesitter parsers found"
    fi
  else
    info "Parser directory not found (parsers may be in a different location)"
  fi
}

check_config() {
  log ""
  log "${BLUE}=== Config ===${NC}"

  if [[ -f "$NVIM_CONFIG/init.lua" ]]; then
    pass "init.lua exists"
  else
    fail "init.lua not found at $NVIM_CONFIG/init.lua"
  fi

  for dir in "lua/config" "lua/custom/plugins" "lua/kickstart/plugins"; do
    if [[ -d "$NVIM_CONFIG/$dir" ]]; then
      pass "$dir/ exists"
    else
      fail "$dir/ not found"
    fi
  done
}

# --- Main ---

checks=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)        checks=(binary startup plugins lsp treesitter config); shift ;;
    --binary)     checks+=(binary); shift ;;
    --startup)    checks+=(startup); shift ;;
    --plugins)    checks+=(plugins); shift ;;
    --lsp)        checks+=(lsp); shift ;;
    --treesitter) checks+=(treesitter); shift ;;
    -q|--quiet)   QUIET=true; shift ;;
    -h|--help)    show_help; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      show_help >&2
      exit 1 ;;
  esac
done

# Default to all checks
if [[ ${#checks[@]} -eq 0 ]]; then
  checks=(binary plugins lsp treesitter config)
fi

log "${BLUE}Neovim Health Check${NC}"

for check in "${checks[@]}"; do
  case "$check" in
    binary)     check_binary ;;
    startup)    check_startup ;;
    plugins)    check_plugins ;;
    lsp)        check_lsp ;;
    treesitter) check_treesitter ;;
    config)     check_config ;;
  esac
done

log ""
if (( FAILED > 0 )); then
  log "${RED}$FAILED check(s) failed.${NC}"
  exit 1
else
  log "${GREEN}All checks passed.${NC}"
  exit 0
fi
