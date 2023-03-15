#!/bin/bash

# =====================
# Install Nerd-Font
# +++++++++++++++++++++

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

# ---------------

# Set up variables for API URL and font directory
api_url="https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest"
#font_dir="$HOME/.local/share/fonts/NerdFonts"
font_dir="$NERD_FONT"

# Download API response and parse JSON to get available font names
echo "Retrieving font information..."
api_response=$(curl -s -H "Accept: application/vnd.github.v3+json" $api_url)

# Check the exit status of the curl command
if [ $? -ne 0 ]; then
  # If the curl command failed, print an error message and exit with a non-zero exit code
  echo "Error: Failed to retrieve font information from ${api_url}" >&2
  exit 1
fi

# Extract font name from the API
font_names=$(echo $api_response | jq -r '.assets[].name' | sed -e "s/^[^a-zA-Z0-9]*//" -e "s/\(.zip\)\?\([^a-zA-Z0-9 ]*\)$//g" | sort -u)

# Check if any fonts were found
if [[ -z $font_names ]]; then
  echo "No fonts found. Aborting installation."
  exit 1
fi

# Display font list with indices
echo "Available fonts:"
echo "$font_names" | nl -w 3 -s ') ' | pr -at2

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

  echo "Invalid input. Please enter a valid index or font name, or enter Q/q to quit."
done

# Abort if no font specified
if [[ -z $font_name ]]; then
  echo "Font not specified. Aborting installation."
  exit 1
fi

extract_dir="$(local_nerd_font_dir "$font_name" "$font_dir")"
# Check if font already exists
if ls "${extract_dir}" 2>/dev/null | grep ".*Complete.\(otf\|ttf\)$" > /dev/null 2>&1; then
  echo "Font already exists. Aborting installation."
  exit 1
fi

# get the asset url from latest release information for the NerdFont from GitHub
asset_url=$(echo "$api_response" | jq -r --arg FONT "$font_name" '.assets[] | select(.name == ($FONT + ".zip")) | .browser_download_url')

# make sure the asset URL is not empty
if [ -z "$asset_url" ]; then
  echo "Error: could not find asset url for '${font_name}' in latest release."
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

# get font file names that match the given pattern
fonts_tobe_installed=$(zipinfo -1 "${tmp_dir}/${font_name}.zip" | grep ".*Complete\.\(ttf\|otf\)$" | grep -iv 'Windows')

# check if file names for target font files are successfully extracted
if [[ $? -ne 0 || -z $fonts_tobe_installed ]]; then
  echo "Erorr: Failed to extract information for font files in '${tmp_dir}/${font_name}.zip'"
  exit 1
fi

# check if the font folder already exists
if [ -z "$extract_dir" ]; then
  echo "Error: failed to composed installation path with base director: ${font_dir} and font name: ${font_name}."
  exit 1
elif [ -d "$extract_dir" ]; then
  echo "The local directory for font ${font_name} already existed at ${extract_dir}. Uninstall the font before installation."
  echo "Aborting installation."
  exit 0
else
  mkdir -p "$extract_dir"
fi

echo -e "The following font files will be extracted to '${extract_dir}'\n"
echo "$fonts_tobe_installed"

# extract only the required files to the local directory using bsdtar
echo "$fonts_tobe_installed"| xargs -d '\n' unzip -qo "${tmp_dir}/${font_name}.zip" -d "$extract_dir"

# check if the font files were extracted successfully
if [ $? -eq 0 ]; then
  echo -e "\nThe '${font_name}' Nerd-Font has been installed to '${extract_dir}'."
else
  echo -e "\nError: failed to install the nerd-font '${font_name}' font."
  clean_up
  exit 2
fi

# clean the tmp folder
clean_up "$tmp_dir" "$tmp_dir_base"
