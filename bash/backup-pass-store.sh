#!/bin/bash

# Set your GitHub username and repository name
GH_USERNAME="yourusername"
GH_REPO="your-repository"

# Set the path to your password store directory
PASS_DIR="$HOME/.password-store"

# Clone the GitHub repository if it doesn't exist locally
if [ ! -d "$GH_REPO" ]; then
    git clone git@github.com:$GH_USERNAME/$GH_REPO.git
fi

# Update the local repository to ensure we have the latest changes
cd $GH_REPO
git pull origin main

# Copy the password store directory to the local repository
cp -R $PASS_DIR/* .

# Add and commit changes to the repository
git add .
git commit -m "Backup password store"
git push origin main

# Print a success message
echo "Password store backed up to GitHub repository."

# Sync the password store with the GitHub repository
if [ "$1" = "sync" ]; then
    # Pull changes from the repository
    git pull origin main
    
    # Copy the updated password store directory to the system
    cp -R ./* $PASS_DIR
    
    # Print a success message
    echo "Password store synchronized with GitHub repository."
fi

# Restore the password store from the GitHub repository
if [ "$1" = "restore" ]; then
    # Make sure the password store directory exists
    mkdir -p $PASS_DIR
    
    # Remove existing passwords
    rm -rf $PASS_DIR/*

    # Clone the repository to a temporary directory
    TMP_DIR=$(mktemp -d)
    git clone git@github.com:$GH_USERNAME/$GH_REPO.git $TMP_DIR
    
    # Copy the password store directory to the system
    cp -R $TMP_DIR/* $PASS_DIR
    
    # Cleanup the temporary directory
    rm -rf $TMP_DIR
    
    # Print a success message
    echo "Password store restored from GitHub repository."
fi
