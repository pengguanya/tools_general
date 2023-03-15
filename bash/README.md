# Install Nerd-Font

This bash script installs a Nerd Font of the user's choice by retrieving the latest release information from the GitHub API, downloading the font zip file, extracting only the required font files, and installing them to a specified font directory. It also checks if the font already exists and prompts the user to choose a font if multiple are available. Important features include using curl to retrieve the API response, parsing JSON with jq to extract font names and asset URLs, creating a temporary directory for font downloads, and using bsdtar to extract only the required font files.

# Usage
```
./nerd_font.sh
```
Then select the font you want to install with index. The font files `.ttf` or `.otf` will be downloaded to `$HOME/$NERD_FONT/<FontName>`. User can define own `$NERD_FONT` environmental variable to specifiy the local path or modify it directly in the script.
