#!/bin/bash
# Screen Control Script
# Author: Guanya Peng
# Description: This script allows you to turn on or off a specified monitor using xrandr.

# Function to execute xrandr with output redirection
run_xrandr() {
    local monitor="$1"
    local action="$2"
    xrandr --output "$monitor" "$action" > /dev/null 2>&1
}

# Function to control the screen state
control_screen() {
    local monitor="$1"
    local action="$2"
    
    if [ "$action" == "on" ]; then
        run_xrandr "$monitor" "--auto"
    elif [ "$action" == "off" ]; then
        run_xrandr "$monitor" "--off"
    else
        echo "Invalid option. Use 'on' to turn the screen on or 'off' to turn it off." > /dev/null
        exit 1
    fi
}

# Check if monitor and action arguments are provided
if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 <monitor_name> on|off" > /dev/null
    exit 1
fi

# Call the control_screen function with the provided monitor and action arguments
control_screen "$1" "$2"
