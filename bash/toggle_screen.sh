#!/bin/bash
# Screen Control Script
# Author: Guanya Peng
# Description: This script allows you to toggle the specified monitor using xrandr.

# Function to execute xrandr with output redirection
run_xrandr() {
    local monitor="$1"
    local action="$2"
    xrandr --output "$monitor" "$action" > /dev/null 2>&1
    return $?
}

# Function to check if the screen is on
is_screen_on() {
    local monitor="$1"
    xrandr | grep "$monitor connected" | grep -q "[0-9]\+x[0-9]\+"
}

# Function to display a message, but only if not in silent mode
display_message() {
    local message="$1"
    if [ "$SILENT" != "true" ]; then
        echo "$message"
    fi
}

# Function to toggle the screen state
toggle_screen() {
    local monitor="$1"
    
    if is_screen_on "$monitor"; then
        if run_xrandr "$monitor" "--off"; then
            display_message "Screen turned off."
        else
            display_message "Error turning off the screen."
            exit 1
        fi
    else
        if run_xrandr "$monitor" "--auto"; then
            display_message "Screen turned on."
        else
            display_message "Error turning on the screen."
            exit 1
        fi
    fi
}

# Check if monitor argument is provided
if [ -z "$1" ]; then
    echo "Usage: $0 [-s] <monitor_name>"
    exit 1
fi

# Parse command-line arguments
SILENT="false"

while getopts "s" opt; do
    case "$opt" in
        s) SILENT="true";;
    esac
done

# Shift the options so that $1 is the monitor name
shift $((OPTIND-1))

# Call the toggle_screen function with the provided monitor argument
toggle_screen "$1"

