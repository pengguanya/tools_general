#!/bin/bash
#
# Script Name: nvim-update.sh
# Description: Download and install the latest stable Neovim AppImage
# Usage: nvim-update [--check | --install] [--version <tag>] [-h]
# Requirements: curl, jq (optional, for JSON parsing)
# Example: nvim-update --check
#          nvim-update --install
#          nvim-update --install --version v0.11.7
#

set -euo pipefail

INSTALL_DIR="$HOME/.local/bin"
BACKUP_DIR="$INSTALL_DIR/.nvim-backups"
NVIM_BIN="$INSTALL_DIR/nvim"
MAX_BACKUPS=3
GITHUB_API="https://api.github.com/repos/neovim/neovim/releases/latest"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

show_help() {
  cat << 'EOF'
Usage: nvim-update [OPTIONS]

Download and install the latest stable Neovim AppImage.

Options:
  --check           Show current vs latest version (default)
  --install         Download and install the latest (or specified) version
  --version <tag>   Install a specific version (e.g., v0.11.7)
  -h, --help        Show this help message

The binary is installed to ~/.local/bin/nvim.
Backups are kept in ~/.local/bin/.nvim-backups/ (3 most recent).

Architecture is auto-detected (x86_64 or arm64).
If FUSE is unavailable, the AppImage is extracted automatically.
EOF
}

get_current_version() {
  if [[ -x "$NVIM_BIN" ]]; then
    "$NVIM_BIN" --version 2>/dev/null | head -1 | grep -oP 'v[\d.]+' || echo "unknown"
  else
    echo "not installed"
  fi
}

get_arch_asset_name() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64)  echo "nvim-linux-x86_64.appimage" ;;
    aarch64) echo "nvim-linux-arm64.appimage" ;;
    *)
      echo -e "${RED}Error: Unsupported architecture: $arch${NC}" >&2
      exit 1
      ;;
  esac
}

fetch_latest_release() {
  local response
  response="$(curl -s --connect-timeout 10 --max-time 30 "$GITHUB_API" 2>/dev/null)" || {
    echo -e "${RED}Error: Cannot reach GitHub API. Check your internet connection.${NC}" >&2
    exit 1
  }

  # Check for rate limiting
  if echo "$response" | grep -q '"message".*rate limit' 2>/dev/null; then
    echo -e "${RED}Error: GitHub API rate limit exceeded.${NC}" >&2
    echo -e "${YELLOW}Use --version <tag> to install a specific version manually.${NC}" >&2
    exit 1
  fi

  echo "$response"
}

extract_tag() {
  local response="$1"
  echo "$response" | grep -oP '"tag_name"\s*:\s*"\K[^"]+' | head -1
}

extract_asset_url() {
  local response="$1"
  local asset_name="$2"
  echo "$response" | grep -oP '"browser_download_url"\s*:\s*"\K[^"]*'"$asset_name"'' | head -1
}

cleanup_backups() {
  if [[ -d "$BACKUP_DIR" ]]; then
    local count
    count=$(ls -1 "$BACKUP_DIR"/nvim-* 2>/dev/null | wc -l)
    if (( count > MAX_BACKUPS )); then
      ls -1t "$BACKUP_DIR"/nvim-* | tail -n +"$((MAX_BACKUPS + 1))" | xargs rm -f
      echo -e "${BLUE}Cleaned old backups (keeping $MAX_BACKUPS most recent)${NC}"
    fi
  fi
}

do_check() {
  local current_version
  current_version="$(get_current_version)"
  echo -e "${BLUE}Current version:${NC} $current_version"

  local target_version="$1"
  if [[ -n "$target_version" ]]; then
    echo -e "${BLUE}Target version:${NC}  $target_version"
    if [[ "$current_version" == "$target_version" ]]; then
      echo -e "${GREEN}Already at target version.${NC}"
    else
      echo -e "${YELLOW}Update available: $current_version -> $target_version${NC}"
    fi
    return
  fi

  echo -e "${BLUE}Fetching latest release info...${NC}"
  local response
  response="$(fetch_latest_release)"
  local latest_version
  latest_version="$(extract_tag "$response")"

  if [[ -z "$latest_version" ]]; then
    echo -e "${RED}Error: Could not parse latest version from GitHub API.${NC}" >&2
    exit 1
  fi

  echo -e "${BLUE}Latest version:${NC}  $latest_version"

  if [[ "$current_version" == "$latest_version" ]]; then
    echo -e "${GREEN}Already up to date.${NC}"
  else
    echo -e "${YELLOW}Update available: $current_version -> $latest_version${NC}"
  fi
}

do_install() {
  local target_version="$1"
  local asset_name
  asset_name="$(get_arch_asset_name)"

  local current_version
  current_version="$(get_current_version)"

  local download_url

  if [[ -n "$target_version" ]]; then
    # Build URL for specific version
    download_url="https://github.com/neovim/neovim/releases/download/${target_version}/${asset_name}"
    echo -e "${BLUE}Target version:${NC} $target_version"
  else
    echo -e "${BLUE}Fetching latest release info...${NC}"
    local response
    response="$(fetch_latest_release)"
    target_version="$(extract_tag "$response")"
    download_url="$(extract_asset_url "$response" "$asset_name")"

    if [[ -z "$target_version" || -z "$download_url" ]]; then
      echo -e "${RED}Error: Could not determine download URL.${NC}" >&2
      exit 1
    fi

    echo -e "${BLUE}Latest version:${NC} $target_version"
  fi

  # Check if already at target
  if [[ "$current_version" == "$target_version" ]]; then
    echo -e "${GREEN}Already at $target_version. Nothing to do.${NC}"
    exit 0
  fi

  echo -e "${BLUE}Current version:${NC} $current_version"
  echo -e "${BLUE}Asset:${NC} $asset_name"
  echo ""

  # Create directories
  mkdir -p "$INSTALL_DIR" "$BACKUP_DIR"

  # Backup current binary
  if [[ -f "$NVIM_BIN" ]]; then
    local backup_name="nvim-$(date +%Y%m%d-%H%M%S)"
    cp "$NVIM_BIN" "$BACKUP_DIR/$backup_name"
    echo -e "${GREEN}Backed up current binary to $BACKUP_DIR/$backup_name${NC}"
    cleanup_backups
  fi

  # Download to temp file
  local tmp_file
  tmp_file="$(mktemp "$INSTALL_DIR/nvim-download-XXXXXX")"
  trap 'rm -f "$tmp_file"' EXIT

  echo -e "${BLUE}Downloading $asset_name...${NC}"
  if ! curl -L --connect-timeout 15 --max-time 300 --progress-bar -o "$tmp_file" "$download_url"; then
    echo -e "${RED}Error: Download failed.${NC}" >&2
    exit 1
  fi

  chmod +x "$tmp_file"

  # Test if FUSE is available and the AppImage runs
  if [[ -e /dev/fuse ]]; then
    echo -e "${BLUE}Testing AppImage with FUSE...${NC}"
    if timeout 10 "$tmp_file" --version >/dev/null 2>&1; then
      # FUSE works, install directly
      mv "$tmp_file" "$NVIM_BIN"
      trap - EXIT
      echo -e "${GREEN}Installed $target_version to $NVIM_BIN${NC}"
    else
      echo -e "${YELLOW}FUSE test failed, trying extraction...${NC}"
      _install_extracted "$tmp_file"
    fi
  else
    echo -e "${YELLOW}FUSE not available, extracting AppImage...${NC}"
    _install_extracted "$tmp_file"
  fi

  # Verify
  echo ""
  local installed_version
  installed_version="$("$NVIM_BIN" --version 2>/dev/null | head -1)"
  echo -e "${GREEN}Verified: $installed_version${NC}"
}

_install_extracted() {
  local appimage="$1"
  local extract_dir
  extract_dir="$(mktemp -d "$INSTALL_DIR/nvim-extract-XXXXXX")"

  cd "$extract_dir"
  "$appimage" --appimage-extract >/dev/null 2>&1

  if [[ ! -f "squashfs-root/usr/bin/nvim" ]]; then
    echo -e "${RED}Error: Extraction failed -- nvim binary not found in squashfs-root.${NC}" >&2
    rm -rf "$extract_dir"
    exit 1
  fi

  # Install the extracted binary and runtime
  local nvim_extracted_dir="$INSTALL_DIR/.nvim-extracted"
  rm -rf "$nvim_extracted_dir"
  mv squashfs-root "$nvim_extracted_dir"
  cd "$INSTALL_DIR"
  rm -rf "$extract_dir"

  # Create a wrapper script that sets the correct runtime path
  cat > "$NVIM_BIN" << 'WRAPPER'
#!/bin/bash
NVIM_DIR="$(dirname "$(readlink -f "$0")")/.nvim-extracted"
exec "$NVIM_DIR/usr/bin/nvim" "$@"
WRAPPER
  chmod +x "$NVIM_BIN"

  echo -e "${GREEN}Installed extracted AppImage to $INSTALL_DIR/.nvim-extracted/${NC}"
}

# --- Main ---

action="check"
target_version=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)    action="check"; shift ;;
    --install)  action="install"; shift ;;
    --version)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --version requires a tag argument (e.g., v0.11.7)" >&2
        exit 1
      fi
      target_version="$2"; shift 2 ;;
    -h|--help)  show_help; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      show_help >&2
      exit 1 ;;
  esac
done

case "$action" in
  check)   do_check "$target_version" ;;
  install) do_install "$target_version" ;;
esac
