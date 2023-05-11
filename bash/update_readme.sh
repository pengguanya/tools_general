################################################################################
# Description:    Update README.md with script names and descriptions
# Author:         Guanya Peng
# Date:           20230511
# Version:        1.0
# Usage:          bash update_readme.sh [SCRIPTS_FOLDER] [README_FILE]
#
# This script updates the README.md file with script names and descriptions. It
# processes the script files in the specified SCRIPTS_FOLDER and checks if the
# script names exist in the README_FILE. If a script name exists, it prompts
# the user to update the description. If a script name does not exist, it appends
# the script name and description to the README_FILE.
#
# Arguments:
#   SCRIPTS_FOLDER  Path to the folder containing the scripts (default: current path)
#   README_FILE     Path to the README.md file (default: current path/README.md)
#   -h, --help      Display this help information
#
# Note: The README_FILE should contain a table with the following columns:
# | Script Name | Description | Usage |
################################################################################

#!/bin/bash

# Default SCRIPTS_FOLDER and README_FILE values (current path)
SCRIPTS_FOLDER=$(pwd)
README_FILE=$(pwd)/README.md

# Function to display help information
display_help() {
  echo "Usage: update_readme.sh [SCRIPTS_FOLDER] [README_FILE]"
  echo "Update the README.md file with script names and descriptions."
  echo ""
  echo "Arguments:"
  echo "  SCRIPTS_FOLDER  Path to the folder containing the scripts (default: current path)"
  echo "  README_FILE     Path to the README.md file (default: current path/README.md)"
  echo "  -h, --help      Display this help information"
}

# Check if the script is called with the help option
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  display_help
  exit 0
fi

# Check if at least one argument is provided
if [[ $# -ge 1 ]]; then
  # Use the first argument as SCRIPTS_FOLDER
  SCRIPTS_FOLDER=$1

  # Check if a second argument is provided
  if [[ $# -ge 2 ]]; then
    # Use the second argument as README_FILE
    README_FILE=$2
  else
    # Set README_FILE to SCRIPTS_FOLDER/README.md
    README_FILE=$SCRIPTS_FOLDER/README.md
  fi
fi

# Function to extract the header from a script file
extract_header() {
  local script_file="$1"
  local header_start=false

  while IFS= read -r line; do
    if [[ $line =~ ^\#!/bin/bash ]]; then
      header_start=true
    elif [[ $header_start == true ]]; then
      if [[ $line =~ ^# ]]; then
        echo "${line##*#}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
      else
        break
      fi
    fi
  done < "$script_file"
}

# Function to check if a script name exists in the README.md file
script_name_exists() {
  local script_name="$1"
  grep -q "^- \[$script_name\]" "$README_FILE"
}

# Function to update the README.md file with the script name and description
update_readme() {
  local script_name="$1"
  local description="$2"
  local temp_file="$(mktemp)"

  # Check if the script name already exists in the README file
  if script_name_exists "$script_name"; then
    read -p "Script '$script_name' already exists in the README file. Do you want to update it? (y/n): " choice
    if [[ $choice =~ ^[Yy]$ ]]; then
      # Update the existing script description
      sed -e "/^- \[$script_name\]/,/^$/s|^.+$|$description|" "$README_FILE" > "$temp_file"
      mv "$temp_file" "$README_FILE"
      echo "Updated '$script_name' in the README file."
    fi
  else
    # Append the new script name and description to the README file
    echo "- [$script_name] $description" >> "$README_FILE"
    echo "Added '$script_name' to the README file."
  fi
}

# Process each script file in the specified folder
for script_file in "$SCRIPTS_FOLDER"/*.sh; do
  script_name=$(basename "$script_file" .sh)
  description=$(extract_header "$script_file")
  usage=$(grep -Po '(?<=^# Usage:).+' "$script_file" | sed -e 's/^[[:space:]]*//')
  script_line="| $script_name | $description | $usage |"

  # Check if the script name already exists in the README file
  if script_name_exists "$script_name"; then
    read -p "Script '$script_name' already exists in the README file. Do you want to update it? (y/n): " choice
    if [[ $choice =~ ^[Yy]$ ]]; then
      # Update the existing script description
      sed -i "/^- \[$script_name\]/,/^$/c$script_line" "$README_FILE"
      echo "Updated '$script_name' in the README file."
    fi
  else
    # Append the new script name and description to the README file
    echo "$script_line" >> "$README_FILE"
    echo "Added '$script_name' to the README file."
  fi
done
