#!/bin/bash

# 1. Identify the user who needs the reset
# If run via sudo, it targets the original user; otherwise, the current user.
TARGET_USER=${SUDO_USER:-$(whoami)}

# 2. Check for root privileges (required to clear faillock)
if [ "$EUID" -ne 0 ]; then
  echo "Error: You must run this as root (e.g., 'wsl -u root ./reset_lockout.sh')"
  exit 1
fi

# 3. Perform the reset
echo "Resetting faillock for user: $TARGET_USER..."
faillock --user "$TARGET_USER" --reset

if [ $? -eq 0 ]; then
  echo "Success: Lockout cleared for $TARGET_USER."
else
  echo "Error: Failed to reset lockout."
  exit 1
fi
