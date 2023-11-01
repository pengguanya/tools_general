#!/bin/bash

terminal="alacritty -e"
dmeditor="nvim"

declare -a options=(
"alacritty - $XDG_CONFIG_HOME/alacritty/alacritty.toml"
"bashrc - $HOME/.bashrc"
"bash_profile - $HOME/.bash_profile"
"bash_prompt - $HOME/.bash_prompt/bash_prompt.bash"
"nvim - $XDG_CONFIG_HOME/nvim/init.lua"
"profilHOME/.confige - $HOME/.profile"
"ssh - $HOME/.ssh/config"
"tmux-general - $HOME/.tmux.conf"
"tmux-master - $HOME/.tmux/config/master.tmux.conf"
"tmux-tvim - $HOME/.tmux-tvim.conf"
"xmonad - $HOME/.xmonad/xmonad.hs"
"xmobar - $XDG_CONFIG_HOME/xmobar/xmobarrc"
"quit"
)

# Format the sorted array for dmenu with two columns
formatted_options=$(printf "%s\n" "${options[@]}" | awk -F' - ' '{printf "%-20s%s\n", $1, $2}')

# Print each option from the sorted array on separate lines
# for option in "${sorted_options[@]}"; do
#   echo "$option"
# done

#echo "${sorted_options[@]}"
# Pipe the formatted array to dmenu
selected_option=$(echo -e "$formatted_options" | dmenu -b -i -l 30 -p "Edit Config:")

# Extract the option and path  
option=$(printf '%s\n' "${selected_option}" | awk '{print $1}')  
path=$(printf '%s\n' "${selected_option}" | awk '{print $NF}') 

terminate_program() {  
  echo "Program terminated."  
  exit 1  
} 

if [[ "$option" == "quit" ]] || [[ -z "$option" ]]; then  
    terminate_program  
else  
  $terminal $dmeditor "$path"  
fi  