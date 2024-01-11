################################################################################
# Description:    Nerd Font Installer Script
# Author:         Guanya Peng
# Date:           20230511
# Version:        1.0
# Usage:          bash nerd_font.sh
# 
# This script is used to install Nerd Fonts on your system. It checks for the 
# required dependencies (curl, jq, zipinfo, unzip), retrieves the latest font 
# information from the GitHub API, allows you to choose a font to install, 
# downloads the font archive, and extracts the font files to the specified 
# directory. If the font is already installed or the font directory already 
# exists, the script will abort the installation.
# 
# Usage:
#   1. Ensure that you have the required dependencies installed (curl, jq, 
#      zipinfo, unzip).
#   2. Open a terminal and navigate to the directory containing this script.
#   3. Run the script using the following command:
#      bash nerd_font_installer.sh
#
# Note: This script assumes that you have permission to write to the font 
# directory specified in the script (default: $HOME/.local/share/fonts/NerdFonts). 
# If you do not have write access to that directory, you may need to modify the 
# `font_dir` variable in the script.
################################################################################

#!/usr/bin/env bash

set -euo pipefail

# Check dependencies
command -v curl >/dev/null 2>&1 || { echo >&2 "curl is required but not installed. Aborting."; exit 1; }
command -v jq >/dev/null 2>&1 || { echo >&2 "jq is required but not installed. Aborting."; exit 1; }
command -v zipinfo >/dev/null 2>&1 || { echo >&2 "zipinfo is required but not installed. Aborting."; exit 1; }
command -v unzip >/dev/null 2>&1 || { echo >&2 "unzip is required but not installed. Aborting."; exit 1; }

# --- Functions ---

# Function to clean up temporary directories and files
clean_up() {
  local tmpdir="$1"
  local tmpdirbase="$2"
  rm -rf "${tmpdir}"
  rm -rf "${tmpdirbase}"
}

# Function to generate sanitized name from a string
sanitize_font_name() {
  local name=$1
  # remove leading/trailing spaces
  name=$(echo "$name" | sed -e 's/^ *//' -e 's/ *$//')
  # replace multiple spaces with a single underscore
  name=$(echo "$name" | sed -e 's/  */_/g')
  # remove all non-alphanumeric characters except for periods, underscores, and hyphens
  name=$(echo "$name" | sed -e 's/[^[:alnum:]._-]//g' -e 's/_\./\./g' -e 's/_\+/_/g')
  echo "$name"
}

# Function to compose path for the folder of local Nerd Font installation
local_nerd_font_dir() {
  local fontname="$1"
  local basedir="$2"
  local nerdfontdir="$(sanitize_font_name "$fontname")"
  echo "${basedir}/${nerdfontdir}"
}

# Function to uninstall a font
function uninstall_font {
  local fontname="$1"
  local basedir="$2"
  local fontdirname="$(sanitize_font_name "$fontname")" 
  local fontdirpath="$(local_nerd_font_dir $fontname $basedir)"
  if [[ -z $basedir ]]; then
    echo "Invalid base directory: '${basedir}'"
  elif [[ -z $fontname || -z $fontdirname ]]; then
    echo "Invalid font name: '${fontdirname}' (sanitized: '${fontdirname}')."
  elif [[ "$fontdirname" == *".."* ]]; then
    echo "Invalid font name: '${fontdirname}'. Contains '..'."
  elif [ -d "$fontdirpath" ]; then
    if [[ $(find "$fontdirpath" -maxdepth 1 -type d | wc -l) -ne 1 ]]; then
      echo "Invalid font directory '${fontdirpath}'"
      echo "It should contain only font files (*.ttf/*.otf) and no subfolders."
      exit 1
    elif [[ $(find "$fontdirpath" -maxdepth 1 -type f \( -iname \*.ttf -o -iname \*.otf \) | wc -l) -eq 0 ]]; then
      echo "No font files (*.ttf/*.otf) found in '${fontdirpath}'"
      exit 1
    else 
      rm -rf "$fontdirpath"
      echo "Uninstalled font '${fontname}'."
    fi
  else
    echo "Could not find installed font '${fontname}'."
    exit 1
  fi
}

# Define the function to check if a font is installed
check_font_installed() {
  local font_name="$1"
  local path_to_fonts="$2"
  local sanitized_font_name="$(sanitize_font_name "$font_name")"
  local thisfontdir="${path_to_fonts}/${sanitized_font_name}"

  if [ -z "$sanitized_font_name" ]; then
    echo "Error: sanitized font name is empty for font '$font_name'" >&2
    exit 1
  fi

  # Check if the sanitized font name matches any folder name under $path_to_fonts
  if [ "$(find "$path_to_fonts" -iname "$sanitized_font_name" -type d | wc -l)" -gt 0 ] && \
     [ "$(find "$thisfontdir" -type f \( -iname '*.ttf' -o -iname '*.otf' \) | wc -l)" -gt 0 ]; then
    echo "[*] ${font_name}"
  else
    echo "$font_name"
  fi
}

# Define the function to loop over each font name and check if it's installed
check_fonts_installed() {
  local font_names="$1"
  local path_to_fonts="$2"
  local font_list=()

  if [ -z "$font_names" ]; then
    echo "Error: font names list is empty" >&2
    return 1
  fi
  
  for font_name in $font_names; do
    if [ -z "$font_name" ]; then
      echo "Error: font name is empty" >&2
      return 1
    fi
    
    updated_font="$(check_font_installed "$font_name" "$path_to_fonts")"
    if [ "$?" -ne 0 ]; then
      echo "Error while checking font '$font_name'" >&2
      return 1
    fi
    font_list+=("$updated_font")
  done

  # Print the list of font names with [*] indicating installed fonts
  printf '%s\n' "${font_list[@]}"
}

# Remove leadning and trailing spaces from text
clean_text() {
    while IFS= read -r line; do
        echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
    done
}

# Filter out specified file type from a list of file names and with a given file type (extension)
filter_files_by_extension() {
    local extension="$1"
    while IFS= read -r line; do
        if [[ "$line" =~ \.$extension$ ]]; then
            echo "$line"
        fi
    done
}

# Clean font names and remove extension from font filenames
clean_fontnames() {
    local fonts="$1"
    local ext="$2"
    echo "$fonts" | sed -e "s/^[^a-zA-Z0-9]*//" -e "s/\(."${ext}"\)\?\([^a-zA-Z0-9 ]*\)$//g" | sort -u
}

# ---------------

# Set up variables for API URL and font directory
api_url="https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest"
font_dir="${NERD_FONT:-$HOME/.local/share/fonts/NerdFonts}"

# Create font folder if not exist
if [[ ! -d "$font_dir" ]]; then
    mkdir -p "$font_dir"
fi

# Download API response and parse JSON to get available font names
echo "Retrieving font information..."
api_response=$(curl -s -H "Accept: application/vnd.github.v3+json" $api_url)

# Check the exit status of the curl command
if [[ $? -ne 0 ]]; then
  # If the curl command failed, print an error message and exit with a non-zero exit code
  echo "Error: Failed to retrieve font information from ${api_url}" >&2
  exit 1
fi

# Extract font name from the API
# Cleaning, and filtering for ".zip" files 
font_zips=$(echo "$api_response" | jq -r '.assets[].name' | clean_text | filter_files_by_extension "zip")

# Clean font names and remove zip extension
font_names=$(clean_fontnames "$font_zips" "zip")

# Check if any fonts were found
if [[ -z $font_names ]]; then
  echo "No fonts found. Aborting installation."
  exit 1
fi

font_names_toprint=$(check_fonts_installed "$font_names" "$font_dir")
# Display font list with indices
echo "Available fonts:"
echo "$font_names_toprint" | nl -w 3 -s ') ' | pr -at2
echo -e "\n [*]: Installed fonts under '${font_dir}'"

# Ask user to choose a font
while true; do
  read -p $'\n'"Enter the index or full name of the font you want to install (Q/q to quit, U/u to uninstall): " font_input

  if [[ "$font_input" =~ ^[Qq]$ ]]; then
    echo "Quitting installation."
    exit 0
  elif [[ "$font_input" =~ ^[Uu]$ ]]; then
    read -p "Enter the index or name of the font you want to uninstall: " font_input
    if [[ "$font_input" =~ ^[0-9]+$ ]]; then
      uninstall_font_name=$(echo "$font_names" | sed -n "${font_input}p")
    else
      uninstall_font_name="$font_input"
    fi
    uninstall_font "$uninstall_font_name" "$font_dir"
    exit 0
  elif [[ "$font_input" =~ ^[0-9]+$ ]]; then
    font_name=$(echo "$font_names" | sed -n "${font_input}p")
    if [[ -n "$font_name" ]]; then
      break
    fi
  elif [[ "$font_names" =~ (^|[[:space:]])"$font_input"($|[[:space:]]) ]]; then
    font_name="$font_input"
    break
  fi

  echo "Invalid input. Please enter a valid index or font name, or enter Q/q to quit, U/u to uninstall."
done

# Abort if no font specified
if [[ -z $font_name ]]; then
  echo "Font not specified. Aborting installation."
  exit 1
fi

extract_dir="$(local_nerd_font_dir "$font_name" "$font_dir")"
# Check if font already exists
if ls "${extract_dir}" 2>/dev/null | grep ".*.\(otf\|ttf\)$" > /dev/null 2>&1; then
  echo "Font already exists. Aborting installation."
  exit 1
fi

# get the asset url from latest release information for the NerdFont from GitHub
asset_url=$(echo "$api_response" | jq -r --arg FONT "$font_name" '.assets[] | select(.name == ($FONT + ".zip")) | .browser_download_url')

# make sure the asset URL is not empty
if [ -z "$asset_url" ]; then
  echo "Error: could not find asset url for '${font_name}' in latest release." >&2
  echo "$asset_url"
  exit 1
fi

# create a temporary directory to download the zip file to
tmp_dir_base="/tmp/font_tmp"
tmp_dir="${tmp_dir_base}/$(date +%y%m%d%h%m%s)-$(openssl rand -hex 6)"
mkdir -p $tmp_dir 


# download the zip file to the temporary directory using wget
wget -q "${asset_url}" -P "${tmp_dir}"

# check the exit status of the wget command
if [ $? -ne 0 ]; then
  echo "Error: Failed to download font ${font_name} from ${asset_url}" >&2
  clean_up "$tmp_dir" "$tmp_dir_base"
  exit 1
fi

# get all font styles
all_styles=$(zipinfo -1 "${tmp_dir}/${font_name}.zip")

# Print available font styles and files
echo "Available font styles:"
font_styles=$(echo "$all_styles" | grep -E '\.(ttf|otf)$' | grep -vi 'Windows')
num_styles=$(echo "$font_styles" | wc -l)
if [ "$num_styles" -eq 0 ]; then
  echo "No font styles found. Aborting installation."
  exit 1
fi

# Determine the column width based on the longest font file name
column_width=$(echo "$font_styles" | awk '{ print length }' | sort -nr | head -n1)

# Format and display the available styles with index numbers
echo "$font_styles" | nl -w 3 -s ') ' | awk -v width="$column_width" -v OFS=' ' '{$1=sprintf("%-3s", $1); $2=sprintf("%-" width "s", $2); print}'

echo

# Prompt user to input a pattern or index
while true; do
  read -p "Enter the pattern to match font styles or an index to install a specific style [Enter: all styles] [Q/q to quit]: " style_input
  
  if [[ "$style_input" =~ ^[Qq]$ ]]; then
    echo "Quitting the program."
    exit 0
  elif [ -z "$style_input" ]; then
    fonts_tobe_installed="$font_styles"
    break
  elif [[ "$style_input" =~ ^[0-9]+$ ]]; then
    style_index=$((style_input - 1))
    if [ "$style_index" -ge 0 ] && [ "$style_index" -lt "$num_styles" ]; then
      fonts_tobe_installed=$(echo "$font_styles" | sed -n "${style_input}p")
      break
    fi
    echo "Invalid input. Please enter a valid index."
  else
    match_found=false
    fonts_tobe_installed=$(echo "$font_styles" | grep -E "$style_input" || true)
    if [ -n "$fonts_tobe_installed" ]; then
      match_found=true
      break
    fi
    echo "No font styles found matching the pattern '$style_input'. Please try again."
  fi
done

# check if file names for target font files are successfully extracted
if [[ $? -ne 0 || -z $fonts_tobe_installed ]]; then
  echo "Erorr: Failed to extract information for font files in '${tmp_dir}/${font_name}.zip'"
  exit 1
fi

# check if the font folder already exists
if [ -z "$extract_dir" ]; then
  echo "Error: failed to composed installation path with base director: ${font_dir} and font name: ${font_name}." >&2
  exit 1
elif [ -d "$extract_dir" ]; then
  echo "The local directory for font ${font_name} already existed at ${extract_dir}. Uninstall the font before installation."
  echo "Aborting installation."
  exit 0
else
  mkdir -p "$extract_dir"
fi

echo -e "\nThe following font files will be extracted to '${extract_dir}'\n"
echo "$fonts_tobe_installed"

# extract only the required files to the local directory using bsdtar
echo "$fonts_tobe_installed" | xargs -d '\n' unzip -qo "${tmp_dir}/${font_name}.zip" -d "$extract_dir"

# check if the font files were extracted successfully
if [ $? -eq 0 ]; then
  echo -e "\nThe '${font_name}' Nerd-Font has been installed to '${extract_dir}'."
else
  clean_up
  echo -e "\nError: failed to install the nerd-font '${font_name}' font." >&2
  exit 2
fi

# clean the tmp folder
clean_up "$tmp_dir" "$tmp_dir_base"
