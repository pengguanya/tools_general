#!/usr/bin/env bash
#
# Script Name: sync_pass.sh
# Description: Mirrors the primary `pass` entry for the current user into all
#              other entries ending with the same username, ensuring password
#              consistency across secrets.
# Usage: ./sync_pass.sh
# Requirements: pass, GNU find, gpg access to the password store
# Safety: Uses `set -euo pipefail` and skips the source entry to avoid loops.
# Example: ./sync_pass.sh && echo "All entries updated"
#
set -euo pipefail

MAIN_ENTRY="Work/Roche/$USER"
PASSWORD="$(pass show "$MAIN_ENTRY" | head -n1)"

ENTRIES=$(find "$HOME/.password-store" -type f -name "*$USER.gpg")

for ENTRY in $ENTRIES; do
  PASS_ENTRY="${ENTRY#$HOME/.password-store/}"
  PASS_ENTRY="${PASS_ENTRY%.gpg}"
  [[ "$PASS_ENTRY" == "$MAIN_ENTRY" ]] && continue
  printf '%s\n' "$PASSWORD" | pass insert -f -m "$PASS_ENTRY" >/dev/null
  echo "Updated: $PASS_ENTRY"
done
