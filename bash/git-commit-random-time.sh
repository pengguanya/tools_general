#!/bin/bash
#
# Script Name: git-commit-random-time.sh
# Description: Creates a git commit whose author/committer timestamp is forced
#              to a random time on a specified day—useful for backfilling demo
#              histories without rewriting the full repo.
# Usage: ./git-commit-random-time.sh YYYY-MM-DD "Commit message"
# Requirements: git
# Notes: Timezone is hardcoded to UTC to keep history deterministic.
# Example: ./git-commit-random-time.sh 2025-01-15 "Docs touch-up"
#
# Check for at least 2 arguments: date and commit message
if [ $# -lt 2 ]; then
  echo "Usage: $0 YYYY-MM-DD \"Your commit message\""
  exit 1
fi

# Extract arguments
DATE_PART=$1
shift
COMMIT_MSG="$*"

# Generate random hour (0–23), minute (0–59), and second (0–59)
HOUR=$(printf "%02d" $((RANDOM % 24)))
MINUTE=$(printf "%02d" $((RANDOM % 60)))
SECOND=$(printf "%02d" $((RANDOM % 60)))

# Construct timestamp with UTC timezone (+0000)
TIMESTAMP="${DATE_PART}T${HOUR}:${MINUTE}:${SECOND}+0000"

# Export dates and make the commit
GIT_AUTHOR_DATE="$TIMESTAMP" \
GIT_COMMITTER_DATE="$TIMESTAMP" \
git commit -m "$COMMIT_MSG"

