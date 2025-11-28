#!/bin/bash
#
# Script Name: new_terminal_same_dir.sh
# Description: Opens a new terminal emulator window rooted in the working
#              directory of the currently focused (or most recent) terminal.
# Usage: TERMINAL=alacritty ./new_terminal_same_dir.sh
# Requirements: xdotool, readlink, target terminal binary in $PATH
# Notes: Falls back to $HOME when no terminal window with a readable cwd is found.
# Example: TERMINAL=kitty ./new_terminal_same_dir.sh
#
# Change this to your terminal command
TERMINAL=alacritty  # or gnome-terminal, kitty, etc.

get_cwd_from_winid() {
    local winid="$1"
    pid=$(xdotool getwindowpid "$winid")
    [ -z "$pid" ] && return 1

    # Find the shell process (bash/zsh) under the terminal process tree
    shell_pid=$(pgrep -P "$pid" -f -u "$USER" "bash|zsh")
    [ -z "$shell_pid" ] && shell_pid="$pid"

    # Get the working directory of the shell process
    cwd=$(readlink -f "/proc/$shell_pid/cwd")
    echo "$cwd"
}

# Try current focused window first
active_win=$(xdotool getactivewindow)
cwd=$(get_cwd_from_winid "$active_win")

# If not a terminal, scan other terminal windows
if [[ ! -d "$cwd" || "$cwd" == "/" ]]; then
    for win in $(xdotool search --onlyvisible --class "$TERMINAL"); do
        cwd=$(get_cwd_from_winid "$win")
        [ -n "$cwd" ] && break
    done
fi

# Fallback to home
[ -z "$cwd" ] && cwd="$HOME"

# Launch terminal
cd "$cwd"
exec $TERMINAL

