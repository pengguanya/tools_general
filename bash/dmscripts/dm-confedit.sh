#!/bin/bash

# Script to edit config file from dmenu

terminal="${TERMINAL:-alacritty} -e"
dmeditor="${EDITOR:-nvim}"

declare -a options=(
"alacritty - $HOME/.config/alacritty/alacritty.toml"
"bash_aliases - $HOME/.bash_aliases"
"bash_profile - $HOME/.bash_profile"
"bash_prompt - $HOME/.bash_prompt/bash_prompt.bash"
"bashrc - $HOME/.bashrc"
"common_env - $HOME/.common_env.sh"
"nvim - $HOME/.config/nvim/init.lua"
"p10k - $HOME/.p10k.zsh"
"profile - $HOME/.profile"
"ssh - $HOME/.ssh/config"
"tmux-general - $HOME/.tmux.conf"
"tmux-master - $HOME/.tmux/config/master.tmux.conf"
"tmux-tvim - $HOME/.tmux-tvim.conf"
"xmobar - $HOME/.config/xmobar/xmobarrc"
"xmonad - $HOME/.xmonad/xmonad.hs"
"zshrc - $HOME/.zshrc"
"quit"
)

# Format the sorted array for dmenu with two columns
formatted_options=$(printf "%s\n" "${options[@]}" | awk -F' - ' '{printf "%-20s%s\n", $1, $2}')

# Pipe the formatted array to dmenu
selected_option=$(echo -e "$formatted_options" | dmenu -b -i -l 30 -p "Edit Config:")

# Extract the option and path
option=$(printf '%s\n' "${selected_option}" | awk '{print $1}')
path=$(printf '%s\n' "${selected_option}" | awk '{print $NF}')

# Exit if no selection or quit selected
if [[ "$option" == "quit" ]] || [[ -z "$option" ]]; then
    exit 0
fi

# Open the selected config file
$terminal $dmeditor "$path"
