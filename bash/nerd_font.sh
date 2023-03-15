#!/bin/bash

# =====================
# Install Nerd-Font
# +++++++++++++++++++++

# Clean a name
clean_name() {
  local name=$1
  # remove leading/trailing spaces
  name=$(echo "$name" | sed -e 's/^ *//' -e 's/ *$//')
  # replace multiple spaces with a single underscore
  name=$(echo "$name" | sed -e 's/  */_/g')
  # remove all non-alphanumeric characters except for periods, underscores, and hyphens
  name=$(echo "$name" | sed -e 's/[^[:alnum:]._-]//g' -e 's/_\./\./g' -e 's/_\+/_/g')
  echo "$name"
}

# Set up variables for API URL and font directory
api_url="https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest"
#font_dir="$HOME/.local/share/fonts/NerdFonts"
font_dir="$NERD_FONT"

# Download API response and parse JSON to get available font names
echo "Retrieving font information..."
api_response=$(curl -s -H "Accept: application/vnd.github.v3+json" $api_url)
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
read -p "Enter the index or full name of the font you want to install: " font_input

# Check if user input is an index or full font name
if [[ "$font_input" =~ ^[0-9]+$ ]]; then
  # User entered an index, so extract corresponding font name
  font_name=$(echo "$font_names" | sed -n "${font_input}p")
else
  # User entered a font name, so use it directly
  font_name="$font_input"
fi

# Abort if no font specified
if [[ -z $font_name ]]; then
  echo "Font not specified. Aborting installation."
  exit 1
fi

# Check if font already exists
if ls "${font_dir}/${font_name}"*Complete.{otf,ttf} >/dev/null 2>&1; then
  echo "Font already exists. Aborting installation."
  exit 1
fi

# get the asset url from latest release information for the NerdFont from GitHub
asset_url=$(echo "$api_response" | jq -r '.assets[].browser_download_url | select(test("'$font_name'.*\\.zip$"))')

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

# get font file names that match the given pattern
fonts_tobe_installed=$(zipinfo -1 "${tmp_dir}/${font_name}.zip" | grep ".*Complete\.\(ttf\|otf\)$" | grep -iv 'Windows')

echo -e "The following font files will be installed to ${font_dir}.\n"
echo "$fonts_tobe_installed"

single_font_dir=$(clean_name "$font_name")
extract_dir="${font_dir}/${single_font_dir}"
# check if the font folder already exists
if [ ! -d "$extract_dir" ]; then
  mkdir -p "$extract_dir"
fi

# extract only the required files to the local directory using bsdtar
echo "$fonts_tobe_installed"| xargs -d '\n' unzip -qo "${tmp_dir}/${font_name}.zip" -d "$extract_dir"

# check if the font files were extracted successfully
if [ $? -eq 0 ]; then
  echo -e "\nThe '${font_name}' Nerd-Font has been installed to '${extract_dir}'."
else
  echo -e "\nError: failed to install the nerd-font '${font_name}' font."
fi

# clean the tmp folder
rm -rf "${tmp_dir}"
rm -rf "${tmp_dir_base}"
