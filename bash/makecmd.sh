#!/bin/bash

if [ $# -eq 0 ]; then
    echo "Usage: $0 <file_name> [link_name]"
    exit 1
fi

file_name="$1"
link_name="$2"

# Extract the base name without extension from the file
base_name=$(basename -- "$file_name")
base_name="${base_name%.*}"

# Get the absolute path of the file
file_path="$(realpath "$file_name")"

# Determine the link name
if [ -z "$link_name" ]; then
    link_name="$base_name"
fi

# Create symbolic link in ~/.local/bin
mkdir -p "$HOME/.local/bin"
ln -s "$file_path" "$HOME/.local/bin/$link_name"

echo "Symbolic link created: $HOME/.local/bin/$link_name"
