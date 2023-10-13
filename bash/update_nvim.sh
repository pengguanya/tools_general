#!/bin/bash

# Define the maximum amount of time to resolve merge conflicts (in seconds)
MAX_WAIT_TIME=240

local_repo="$HOME/.config/nvim"

cd $local_repo

# Add the original repository as a remote
git remote add upstream https://github.com/nvim-lua/kickstart.nvim.git

# Create a new branch
git checkout -b update-fork

# Fetch all the branches of the upstream repository into remote-tracking branches
git fetch upstream

# Merge the changes from the upstream repository into your local update-fork branch
git merge upstream/master

# Check if there are any merge conflicts
if [ -n "$(git status --porcelain | grep '^UU')" ]; then
    echo "There are merge conflicts. Please resolve them within $((MAX_WAIT_TIME / 60)) minutes and type 'y' or 'Y' when you're done."
    read -n 1 -s -r -p ""
    while [ "$REPLY" != "y" ] && [ "$REPLY" != "Y" ]
    do
        echo "Waiting for $((MAX_WAIT_TIME / 60)) minutes to give you time to resolve the conflicts..."
        for (( i=MAX_WAIT_TIME; i>0; i-- ))
        do
            if [ $(($i % 60)) -eq 0 ]; then
                printf "\r%02d:%02d remaining... Please resolve the conflicts." $((i / 60)) $((i % 60))
            fi
            sleep 1
        done
        printf "\n"
        echo "Please resolve the conflicts and type 'y' or 'Y' when you're done."
        read -n 1 -s -r -p ""
    done
fi

# Commit your changes
git commit -m "Update fork"

# Push the changes to your forked repository on GitHub
git push origin update-fork

# Create a pull request from your update-fork branch to your master branch on GitHub

