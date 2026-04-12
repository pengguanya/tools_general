#!/bin/bash
#
# Script Name: pre_migration_backup.sh
# Description: Pre-migration backup — captures everything needed to restore
#              a personal dev environment on a fresh Ubuntu install.
#              Ubuntu-version-agnostic. Does NOT touch corporate configs
#              (rlcaas-*, corporate certs, package channels).
# Usage: pre_migration_backup [BACKUP_DIR]
# Requirements: git, yadm, gpg, tar, docker (optional)
# Example: pre_migration_backup /mnt/usb/backup
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DEFAULT_BACKUP_DIR="$HOME/backup/pre_migration_$TIMESTAMP"

show_help() {
    cat << 'EOF'
Usage: pre_migration_backup [BACKUP_DIR]

Creates a comprehensive backup of your personal dev environment before
an OS upgrade or migration. Captures:

  - System inventory (packages, snaps, flatpaks, language packages)
  - GPG keys (public, private, ownertrust)
  - SSH keys
  - Password store
  - Cloud configs (AWS, gcloud, docker)
  - Docker volumes
  - Git repo status (yadm, tools_general, ai-config)

Does NOT touch: corporate configs (rlcaas-*), certificates, package channels.

Arguments:
  BACKUP_DIR    Where to save backups (default: ~/backup/pre_migration_YYYYMMDD_HHMMSS)

Options:
  -h, --help    Show this help message
  --dry-run     Show what would be backed up without doing it
  --skip-docker Skip Docker volume backup
  --skip-secrets Skip secrets upload to Bitwarden
EOF
}

# Parse arguments
DRY_RUN=false
SKIP_DOCKER=false
SKIP_SECRETS=false
BACKUP_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_help; exit 0 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --skip-docker) SKIP_DOCKER=true; shift ;;
        --skip-secrets) SKIP_SECRETS=true; shift ;;
        -*) echo -e "${RED}Unknown option: $1${NC}"; show_help; exit 1 ;;
        *) BACKUP_DIR="$1"; shift ;;
    esac
done

BACKUP_DIR="${BACKUP_DIR:-$DEFAULT_BACKUP_DIR}"

log_step() { echo -e "\n${BLUE}=== $1 ===${NC}"; }
log_ok()   { echo -e "${GREEN}✓ $1${NC}"; }
log_warn() { echo -e "${YELLOW}⚠ $1${NC}"; }
log_err()  { echo -e "${RED}✗ $1${NC}"; }

if $DRY_RUN; then
    echo -e "${YELLOW}DRY RUN — showing what would be backed up${NC}"
    echo "Backup directory: $BACKUP_DIR"
    echo ""
    echo "Would capture:"
    echo "  - dpkg selections, apt installed, snap list, flatpak list"
    echo "  - pip list, npm globals, cargo installs, R packages"
    echo "  - APT sources.d"
    echo "  - GPG keys (public, private, ownertrust)"
    echo "  - SSH keys (~/.ssh/)"
    echo "  - Password store (~/.password-store/)"
    echo "  - Cloud configs (~/.aws/, ~/.config/gcloud/, ~/.docker/)"
    echo "  - Docker named volumes (if Docker running)"
    echo "  - System info (os-release, uname, lspci, lsusb)"
    echo "  - Git repo status (yadm, tools_general, ai-config)"
    echo ""
    echo "Would verify:"
    echo "  - yadm repo is clean and pushed"
    echo "  - tools_general repo is clean and pushed"
    echo "  - ai-config repo is clean and pushed"
    echo "  - Secrets uploaded to Bitwarden"
    exit 0
fi

# Create backup directory
mkdir -p "$BACKUP_DIR"
echo -e "${BLUE}Backup directory: $BACKUP_DIR${NC}"

# Track what was backed up
SUMMARY=()

########################################
# Step 1: System inventory
########################################
log_step "Step 1: System inventory"

# OS info
cat /etc/os-release > "$BACKUP_DIR/os-release.txt" 2>/dev/null && log_ok "os-release" || log_warn "os-release not found"
uname -a > "$BACKUP_DIR/uname.txt" 2>/dev/null && log_ok "uname"

# Hardware
lspci > "$BACKUP_DIR/lspci.txt" 2>/dev/null && log_ok "lspci" || log_warn "lspci not available"
lsusb > "$BACKUP_DIR/lsusb.txt" 2>/dev/null && log_ok "lsusb" || log_warn "lsusb not available"

# Package lists
dpkg --get-selections 2>/dev/null | grep -v deinstall > "$BACKUP_DIR/dpkg-selections.txt" && \
    log_ok "dpkg selections ($(wc -l < "$BACKUP_DIR/dpkg-selections.txt") packages)" || log_warn "dpkg failed"

apt list --installed 2>/dev/null > "$BACKUP_DIR/apt-installed.txt" && \
    log_ok "apt installed list" || log_warn "apt list failed"

snap list 2>/dev/null > "$BACKUP_DIR/snap-list.txt" && \
    log_ok "snap list ($(wc -l < "$BACKUP_DIR/snap-list.txt") entries)" || log_warn "snap not available"

flatpak list 2>/dev/null > "$BACKUP_DIR/flatpak-list.txt" && \
    log_ok "flatpak list" || log_warn "flatpak not available"

# APT sources
if [[ -d /etc/apt/sources.list.d/ ]]; then
    mkdir -p "$BACKUP_DIR/apt-sources"
    cp -r /etc/apt/sources.list.d/* "$BACKUP_DIR/apt-sources/" 2>/dev/null
    [[ -f /etc/apt/sources.list ]] && cp /etc/apt/sources.list "$BACKUP_DIR/apt-sources/"
    log_ok "APT sources"
fi

SUMMARY+=("System inventory captured")

########################################
# Step 2: Language package lists
########################################
log_step "Step 2: Language package lists"

pip list 2>/dev/null > "$BACKUP_DIR/pip-global.txt" && \
    log_ok "pip packages ($(wc -l < "$BACKUP_DIR/pip-global.txt") entries)" || log_warn "pip not available"

npm list -g --depth=0 2>/dev/null > "$BACKUP_DIR/npm-global.txt" && \
    log_ok "npm global packages" || log_warn "npm not available"

cargo install --list 2>/dev/null > "$BACKUP_DIR/cargo-installed.txt" && \
    log_ok "cargo packages" || log_warn "cargo not available"

# R packages
if command -v Rscript &>/dev/null; then
    Rscript -e 'write.csv(installed.packages()[,c("Package","Version")], row.names=FALSE)' \
        > "$BACKUP_DIR/r-packages.csv" 2>/dev/null && \
        log_ok "R packages" || log_warn "R package list failed"
fi

SUMMARY+=("Language packages captured")

########################################
# Step 3: GPG keys
########################################
log_step "Step 3: GPG keys"

if command -v gpg &>/dev/null; then
    gpg --export --armor > "$BACKUP_DIR/gpg-public-keys.asc" 2>/dev/null && \
        log_ok "GPG public keys"
    gpg --export-secret-keys --armor > "$BACKUP_DIR/gpg-private-keys.asc" 2>/dev/null && \
        log_ok "GPG private keys"
    gpg --export-ownertrust > "$BACKUP_DIR/gpg-ownertrust.txt" 2>/dev/null && \
        log_ok "GPG ownertrust"
    # Restrict permissions on private keys
    chmod 600 "$BACKUP_DIR/gpg-private-keys.asc" 2>/dev/null
    SUMMARY+=("GPG keys exported")
else
    log_warn "gpg not found"
fi

########################################
# Step 4: SSH keys
########################################
log_step "Step 4: SSH keys"

if [[ -d "$HOME/.ssh" ]]; then
    mkdir -p "$BACKUP_DIR/ssh-backup"
    cp -r "$HOME/.ssh/"* "$BACKUP_DIR/ssh-backup/" 2>/dev/null
    chmod 700 "$BACKUP_DIR/ssh-backup"
    chmod 600 "$BACKUP_DIR/ssh-backup/"* 2>/dev/null
    log_ok "SSH keys backed up ($(ls "$BACKUP_DIR/ssh-backup/" | wc -l) files)"
    SUMMARY+=("SSH keys backed up")
else
    log_warn "~/.ssh not found"
fi

########################################
# Step 5: Password store
########################################
log_step "Step 5: Password store"

if [[ -d "$HOME/.password-store" ]]; then
    cp -r "$HOME/.password-store" "$BACKUP_DIR/password-store-backup"
    log_ok "Password store backed up"
    SUMMARY+=("Password store backed up")
else
    log_warn "~/.password-store not found"
fi

########################################
# Step 6: Cloud configs
########################################
log_step "Step 6: Cloud configs (excluding corporate certs)"

mkdir -p "$BACKUP_DIR/cloud-configs"

# AWS (exclude any rlcaas files)
if [[ -d "$HOME/.aws" ]]; then
    cp "$HOME/.aws/config" "$BACKUP_DIR/cloud-configs/aws-config" 2>/dev/null
    cp "$HOME/.aws/credentials" "$BACKUP_DIR/cloud-configs/aws-credentials" 2>/dev/null
    chmod 600 "$BACKUP_DIR/cloud-configs/aws-credentials" 2>/dev/null
    log_ok "AWS config"
fi

# gcloud (config only, not caches/logs)
if [[ -d "$HOME/.config/gcloud" ]]; then
    mkdir -p "$BACKUP_DIR/cloud-configs/gcloud"
    cp "$HOME/.config/gcloud/application_default_credentials.json" \
        "$BACKUP_DIR/cloud-configs/gcloud/" 2>/dev/null
    [[ -d "$HOME/.config/gcloud/configurations" ]] && \
        cp -r "$HOME/.config/gcloud/configurations" "$BACKUP_DIR/cloud-configs/gcloud/"
    log_ok "gcloud config"
fi

# Docker config (auth, not daemon config)
if [[ -f "$HOME/.docker/config.json" ]]; then
    cp "$HOME/.docker/config.json" "$BACKUP_DIR/cloud-configs/docker-config.json" 2>/dev/null
    log_ok "Docker auth config"
fi

SUMMARY+=("Cloud configs backed up")

########################################
# Step 7: Docker volumes
########################################
log_step "Step 7: Docker volumes"

if ! $SKIP_DOCKER && command -v docker &>/dev/null && docker info &>/dev/null; then
    docker ps -a > "$BACKUP_DIR/docker-containers.txt" 2>/dev/null
    docker images > "$BACKUP_DIR/docker-images.txt" 2>/dev/null
    docker volume ls > "$BACKUP_DIR/docker-volumes.txt" 2>/dev/null
    log_ok "Docker inventory captured"

    # Backup named volumes
    mkdir -p "$BACKUP_DIR/docker-volumes"
    while IFS= read -r vol; do
        [[ -z "$vol" || "$vol" == "VOLUME NAME" ]] && continue
        echo -n "  Backing up volume '$vol'... "
        if docker run --rm -v "$vol":/data -v "$BACKUP_DIR/docker-volumes":/backup \
            alpine tar czf "/backup/${vol}.tar.gz" -C /data . 2>/dev/null; then
            echo -e "${GREEN}done${NC}"
        else
            echo -e "${YELLOW}failed (may be in use)${NC}"
        fi
    done < <(docker volume ls -q 2>/dev/null)

    SUMMARY+=("Docker volumes backed up")
else
    if $SKIP_DOCKER; then
        log_warn "Docker backup skipped (--skip-docker)"
    else
        log_warn "Docker not available or not running"
    fi
fi

########################################
# Step 8: Verify git repos
########################################
log_step "Step 8: Verify git repos are clean and pushed"

check_git_repo() {
    local name="$1"
    local dir="$2"
    local git_cmd="$3"  # "git" or "yadm"

    if [[ ! -d "$dir" ]]; then
        log_warn "$name: directory not found ($dir)"
        return
    fi

    local status
    if [[ "$git_cmd" == "yadm" ]]; then
        status=$(yadm status --porcelain 2>/dev/null)
    else
        status=$(git -C "$dir" status --porcelain 2>/dev/null)
    fi

    if [[ -n "$status" ]]; then
        log_err "$name: has uncommitted changes!"
        echo "$status" | head -10 | sed 's/^/    /'
        echo -e "    ${YELLOW}Please commit and push before migrating.${NC}"
    else
        log_ok "$name: clean"
    fi

    # Check if pushed (compare local and remote HEAD)
    local local_head remote_head
    if [[ "$git_cmd" == "yadm" ]]; then
        local_head=$(yadm rev-parse HEAD 2>/dev/null)
        remote_head=$(yadm rev-parse origin/main 2>/dev/null || yadm rev-parse origin/master 2>/dev/null)
    else
        local_head=$(git -C "$dir" rev-parse HEAD 2>/dev/null)
        remote_head=$(git -C "$dir" rev-parse origin/main 2>/dev/null || \
                      git -C "$dir" rev-parse origin/master 2>/dev/null)
    fi

    if [[ -n "$local_head" && -n "$remote_head" ]]; then
        if [[ "$local_head" == "$remote_head" ]]; then
            log_ok "$name: up to date with remote"
        else
            log_err "$name: local and remote differ — push before migrating!"
        fi
    else
        log_warn "$name: could not verify remote status"
    fi
}

check_git_repo "yadm (dotfiles)" "$HOME" "yadm"
check_git_repo "tools_general" "$HOME/tools/general" "git"

# ai-config (bare repo)
if [[ -d "$HOME/.ai-config.git" ]]; then
    ai_status=$(git --git-dir="$HOME/.ai-config.git" --work-tree="$HOME" status --porcelain 2>/dev/null)
    if [[ -n "$ai_status" ]]; then
        log_err "ai-config: has uncommitted changes!"
        echo "$ai_status" | head -10 | sed 's/^/    /'
    else
        log_ok "ai-config: clean"
    fi
else
    log_warn "ai-config: bare repo not found"
fi

SUMMARY+=("Git repos verified")

########################################
# Step 9: Upload secrets to Bitwarden
########################################
log_step "Step 9: Secrets backup"

if ! $SKIP_SECRETS && command -v upload_secrets_to_bitwarden &>/dev/null; then
    echo "Running upload_secrets_to_bitwarden..."
    if upload_secrets_to_bitwarden; then
        log_ok "Secrets uploaded to Bitwarden"
        SUMMARY+=("Secrets uploaded to Bitwarden")
    else
        log_warn "Secrets upload failed — do it manually before migrating"
    fi
elif $SKIP_SECRETS; then
    log_warn "Secrets upload skipped (--skip-secrets)"
else
    log_warn "upload_secrets_to_bitwarden not found in PATH"
fi

########################################
# Step 10: VPN config (non-corporate parts only)
########################################
log_step "Step 10: VPN config (personal scripts only)"

if [[ -d "$HOME/.config/vpn" ]]; then
    mkdir -p "$BACKUP_DIR/vpn-config"
    # Copy VPN method configs but NOT corporate certs/keys (rlcaas-*)
    cp -r "$HOME/.config/vpn/"* "$BACKUP_DIR/vpn-config/" 2>/dev/null
    log_ok "VPN config backed up (personal scripts only)"
    SUMMARY+=("VPN config backed up")
fi

########################################
# Summary
########################################
echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN} ✓ Backup Complete!${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
echo -e "Backup location: ${GREEN}$BACKUP_DIR${NC}"
echo -e "Backup size: $(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)"
echo ""
echo "Contents:"
for item in "${SUMMARY[@]}"; do
    echo "  ✓ $item"
done
echo ""
echo -e "${YELLOW}Before migrating, ensure:${NC}"
echo "  1. All git repos are committed and pushed (check warnings above)"
echo "  2. Copy $BACKUP_DIR to external storage (USB, cloud)"
echo "  3. Optionally: create a full disk image with Clonezilla"
echo ""
echo -e "${YELLOW}After fresh install, restore with:${NC}"
echo "  1. sudo apt install -y git yadm"
echo "  2. yadm clone <your-repo-url>"
echo "  3. yadm bootstrap"
echo "  4. Restore SSH keys:  cp -r $BACKUP_DIR/ssh-backup/* ~/.ssh/"
echo "  5. Restore GPG keys:  gpg --import $BACKUP_DIR/gpg-private-keys.asc"
echo "  6. Restore secrets:   restore_secrets_from_bitwarden"
