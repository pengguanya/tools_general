################################################################################
# Description: Bash script to backup and synchronize a password store with a GitHub repository.
# Author: Guanya Peng
# Date: 20230404
# Version: 1.0
# Usage: bash backup_pass_store.sh [OPTIONS]
#
# This script allows you to backup and synchronize a password store with a
# GitHub repository. It provides options to sync, restore, or perform a normal
# backup of the password store. By default, it performs a normal backup if no
# option is specified.
#
# Options:
#   -s             Sync the password store with the GitHub repository.
#                  This option pulls changes from the repository, copies the
#                  updated password store to the system, adds and commits
#                  changes to the repository with a timestamp.
#   -r [TIMESTAMP] Restore the password store from the GitHub repository.
#                  This option restores the password store to a specific
#                  timestamp. If no timestamp is provided, it restores to
#                  the latest version. The restored password store is copied
#                  to the system.
#
# Dependencies: Git
#               Make sure the Git repository is set up correctly before
#               using this script.
#
# Note: Before running this script, make sure to set the following variables:
#       - GH_USERNAME: Your GitHub username
#       - GH_REPO: Your GitHub repository name
#       - BACKUP_DIR: The directory to store the local backup
#       - GIT_URL_ROCHE: The Git URL for Roche (if applicable)
#       - GIT_URL: The Git URL for GitHub (if applicable)
#       - PASS_DIR: The path to your password store directory
#
################################################################################

#!/bin/bash

# Function to commit
function commit() {
  TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
  COMMIT_MSG="Backup password store - $TIMESTAMP"
  git add .
  git commit -m "$COMMIT_MSG"
  git push origin main
}

# Function to validate time-stamp format
function validate_timestamp() {
  if [[ ! $1 =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\s[0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
    echo "Error: Invalid time-stamp format. Please use format YYYY-MM-DD HH:MM:SS."
    exit 1
  fi
}

# Set your GitHub username and repository name
GH_USERNAME="pengg3"
GH_REPO="pass"
BACKUP_DIR="${HOME}/backup"
GIT_URL_ROCHE="github.roche.com"
GIT_URL="github.com:"

# Set the path to your password store directory
PASS_DIR="$HOME/.password-store"

# Clone the GitHub repository if it doesn't exist locally
if [ ! -d "${BACKUP_DIR}/${GH_REPO}" ]; then
    mkdir -p "${BACKUP_DIR}/${GH_REPO}"
    git clone "git@${GIT_URL_ROCHE}:${GH_USERNAME}/${GH_REPO}.git" "${BACKUP_DIR}/${GH_REPO}"
fi

# Update the local repository to ensure we have the latest changes
cd "${BACKUP_DIR}/${GH_REPO}"

# Dispatch based on script options
while getopts ":s:r:" opt; do
    case $opt in
        s)
            # Sync the password store with the GitHub repository
            # Pull changes from the repository
            git pull origin main

            # Copy the updated password store directory to the system
            cp -R ./* $PASS_DIR

            # Copy back everything from system password store to the backup folder
            cp $PASS_DIR/* .

            # Add and commit changes to the repository with timestamp
            commit

            # Print a success message
            echo "Password store synchronized with GitHub repository."
            ;;
        r)
            # Restore the password store from the GitHub repository
            if [ -n "$OPTARG" ]; then
                # Validate the time-stamp format
                validate_timestamp "$OPTARG"
                # Restore to specific timestamp
                git checkout $(git rev-list -n 1 --before="$OPTARG" main)
            else
                # Restore to latest version
                git checkout main
            fi

            # Make sure the password store directory exists
            mkdir -p $PASS_DIR

            # Remove existing passwords
            rm -rf $PASS_DIR/*

            # Copy the password store directory to the system
            cp -R ./* $PASS_DIR

            # Print a success message
            echo "Password store restored from GitHub repository."

            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            exit 1
            ;;
    esac
done

# If no option is specified, perform a normal backup
if [ $OPTIND -eq 1 ]; then
    echo "No option specified, performing normal backup."
    git pull origin main

    # Check if there are changes to the password store
    CHANGED_FILES=$(find $PASS_DIR -type f -newer "${BACKUP_DIR}/${GH_REPO}" | sed "s|^$PASS_DIR/||")
    if [ -z "$CHANGED_FILES" ]; then
        # No changes, print message and exit
        echo "Password store has not changed. No backup necessary."
        exit 0
    else
        # Changes detected, prompt user to proceed
        echo "The following files have changed in the password store:"
        echo "$CHANGED_FILES"
        read -p "Do you want to backup these changes? (y/n): " CHOICE
        if [ "$CHOICE" != "y" ]; then
            echo "Backup aborted by user."
            exit 0
        fi
    fi
    
    # Copy the password store directory to the local repository
    cp -R $PASS_DIR/* .

    # Add and commit changes to the repository with timestamp
    commit

    # Print a success message
    echo "Password store backed up to GitHub repository."
fi
