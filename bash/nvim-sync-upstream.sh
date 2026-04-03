#!/bin/bash
#
# Script Name: nvim-sync-upstream.sh
# Description: Merge upstream kickstart.nvim changes into the user's fork
# Usage: nvim-sync-upstream [--check | --merge] [--stash] [-h]
# Requirements: git
# Example: nvim-sync-upstream --check
#          nvim-sync-upstream --merge --stash
#

set -euo pipefail

NVIM_CONFIG="${NVIM_CONFIG:-$HOME/.config/nvim}"
UPSTREAM_REMOTE="upstream"
UPSTREAM_BRANCH="master"
LOCAL_BRANCH="master"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

show_help() {
  cat << 'EOF'
Usage: nvim-sync-upstream [OPTIONS]

Merge upstream kickstart.nvim changes into your fork.

Options:
  --check         Show divergence status only (default)
  --merge         Perform the merge from upstream/master
  --stash         Auto-stash uncommitted changes before merge
  -h, --help      Show this help message

After a successful merge, remember to:
  1. cd ~/.config/nvim && git push origin master
  2. yadm add .config/nvim && yadm commit -m "update nvim submodule"

Exit codes:
  0  Success (or no changes needed)
  1  Error
  2  Merge conflicts require manual resolution
EOF
}

ensure_upstream_remote() {
  cd "$NVIM_CONFIG"

  if ! git remote get-url "$UPSTREAM_REMOTE" >/dev/null 2>&1; then
    echo -e "${BLUE}Adding upstream remote...${NC}"
    git remote add "$UPSTREAM_REMOTE" "https://github.com/nvim-lua/kickstart.nvim.git"
    echo -e "${GREEN}Added upstream remote.${NC}"
  fi
}

check_dirty() {
  cd "$NVIM_CONFIG"
  local status
  status="$(git status --porcelain 2>/dev/null)"
  if [[ -n "$status" ]]; then
    return 0  # dirty
  fi
  return 1  # clean
}

do_check() {
  cd "$NVIM_CONFIG"
  ensure_upstream_remote

  echo -e "${BLUE}Fetching upstream...${NC}"
  git fetch "$UPSTREAM_REMOTE" --quiet

  local behind ahead
  behind="$(git rev-list --count "$LOCAL_BRANCH".."$UPSTREAM_REMOTE/$UPSTREAM_BRANCH" 2>/dev/null || echo 0)"
  ahead="$(git rev-list --count "$UPSTREAM_REMOTE/$UPSTREAM_BRANCH".."$LOCAL_BRANCH" 2>/dev/null || echo 0)"

  echo ""
  echo -e "${BLUE}Fork status:${NC}"
  echo -e "  Ahead of upstream:  ${GREEN}$ahead${NC} commit(s)"
  echo -e "  Behind upstream:    ${YELLOW}$behind${NC} commit(s)"

  if (( behind > 0 )); then
    echo ""
    echo -e "${BLUE}Upstream commits not in your fork:${NC}"
    git log --oneline "$LOCAL_BRANCH".."$UPSTREAM_REMOTE/$UPSTREAM_BRANCH" | head -20
    echo ""
    echo -e "${YELLOW}Run 'nvim-sync-upstream --merge' to merge these changes.${NC}"
  else
    echo ""
    echo -e "${GREEN}Fork is up to date with upstream.${NC}"
  fi

  if check_dirty; then
    echo ""
    echo -e "${YELLOW}Note: Working tree has uncommitted changes:${NC}"
    git status --short
  fi
}

do_merge() {
  local use_stash="$1"

  cd "$NVIM_CONFIG"
  ensure_upstream_remote

  # Handle dirty working tree
  local stashed=false
  if check_dirty; then
    if [[ "$use_stash" == true ]]; then
      echo -e "${BLUE}Stashing uncommitted changes...${NC}"
      git stash push -m "nvim-sync-upstream auto-stash $(date +%Y%m%d-%H%M%S)"
      stashed=true
    else
      echo -e "${RED}Error: Working tree has uncommitted changes.${NC}" >&2
      echo -e "${YELLOW}Either commit your changes, or use --stash to auto-stash them.${NC}" >&2
      echo ""
      git status --short >&2
      exit 1
    fi
  fi

  echo -e "${BLUE}Fetching upstream...${NC}"
  git fetch "$UPSTREAM_REMOTE" --quiet

  local behind
  behind="$(git rev-list --count "$LOCAL_BRANCH".."$UPSTREAM_REMOTE/$UPSTREAM_BRANCH" 2>/dev/null || echo 0)"

  if (( behind == 0 )); then
    echo -e "${GREEN}Already up to date with upstream. Nothing to merge.${NC}"
    if [[ "$stashed" == true ]]; then
      echo -e "${BLUE}Restoring stashed changes...${NC}"
      git stash pop
    fi
    exit 0
  fi

  echo -e "${BLUE}Merging $behind commit(s) from upstream/$UPSTREAM_BRANCH...${NC}"

  if git merge "$UPSTREAM_REMOTE/$UPSTREAM_BRANCH" --no-edit 2>&1; then
    echo ""
    echo -e "${GREEN}Merge successful.${NC}"

    if [[ "$stashed" == true ]]; then
      echo -e "${BLUE}Restoring stashed changes...${NC}"
      if ! git stash pop 2>/dev/null; then
        echo -e "${YELLOW}Warning: Could not auto-restore stash (may conflict). Use 'git stash pop' manually.${NC}"
      fi
    fi

    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo "  1. Test your config:  nvim +checkhealth"
    echo "  2. Update plugins:    nvim --headless '+Lazy! sync' +qa"
    echo "  3. Push to fork:      cd ~/.config/nvim && git push origin $LOCAL_BRANCH"
    echo "  4. Update yadm:       yadm add .config/nvim && yadm commit -m 'update nvim submodule'"
  else
    echo ""
    echo -e "${RED}Merge has conflicts.${NC}"
    echo ""
    echo -e "${YELLOW}Conflicted files:${NC}"
    git diff --name-only --diff-filter=U

    echo ""
    echo -e "${BLUE}Resolution hints:${NC}"
    echo "  - init.lua: Keep your server list, colorscheme, and 'require config' line."
    echo "    Accept upstream structural changes."
    echo "  - lazy-lock.json: Accept either side, then run :Lazy sync in nvim."
    echo "  - lua/custom/plugins/*: Should not conflict (upstream doesn't touch these)."
    echo ""
    echo "After resolving:"
    echo "  git add . && git merge --continue"

    if [[ "$stashed" == true ]]; then
      echo ""
      echo -e "${YELLOW}Your stashed changes can be restored after merge:${NC}"
      echo "  git stash pop"
    fi

    exit 2
  fi
}

# --- Main ---

action="check"
use_stash=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)   action="check"; shift ;;
    --merge)   action="merge"; shift ;;
    --stash)   use_stash=true; shift ;;
    -h|--help) show_help; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      show_help >&2
      exit 1 ;;
  esac
done

case "$action" in
  check) do_check ;;
  merge) do_merge "$use_stash" ;;
esac
