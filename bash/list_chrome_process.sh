#!/bin/bash

# Script to list all Google Chrome related running processes

echo "Listing all Google Chrome related running processes..."

# Define the script name to exclude it from the results
SCRIPT_NAME="list_chrome_process"

# Using pgrep to find all process IDs related to 'chrome'
# Exclude any line that contains the script name
pgrep -a chrome | grep -v "$SCRIPT_NAME" | cut -d ' ' -f 1 | while read pid; do
    ps $pid
done
