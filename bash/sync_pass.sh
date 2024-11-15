#!/bin/bash

# Path to the main entry you will update manually
MAIN_ENTRY="Work/Roche/$USER"

# Get the password from the main entry
PASSWORD=$(pass show "$MAIN_ENTRY")

# Find all entries that end with $USER
ENTRIES=$(find ~/.password-store -type f -name "*$USER.gpg")

# Update all entries that end with $USER with the new password
for ENTRY in $ENTRIES; do
    # Convert the file path to the pass path
    PASS_ENTRY=$(echo "$ENTRY" | sed "s|$HOME/.password-store/||" | sed 's|.gpg||')

    # Ensure it is not the main entry itself
    if [ "$PASS_ENTRY" != "$MAIN_ENTRY" ]; then
        echo "$PASSWORD" | pass insert -f "$PASS_ENTRY"
    fi
done
