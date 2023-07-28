################################################################################
# Description:   Bash script to detect and adjust display configuration.
# Author:        Your Name
# Date:          20230531
# Version:       1.0
# Usage:         bash detect_monitor.sh
#
# This script detects the presence of an external monitor and adjusts the display
# configuration accordingly. If an external monitor is connected, it turns off the
# laptop display and sets the external monitor to its preferred resolution. If no
# external monitor is detected, it turns on the laptop display.
#
# Dependencies: xrandr
#
################################################################################

#!/bin/bash

# Get the output name of the laptop display
laptop_display=$(xrandr | grep " connected primary" | awk '{print $1}')

# Check if an external monitor is connected
external_monitor_connected=$(xrandr | grep " connected" | grep -v "^$laptop_display" | awk '{print $1}')

if [ -n "$external_monitor_connected" ]; then
    # External monitor connected
    xrandr --output "$laptop_display" --off --output "$external_monitor_connected" --auto
else
    # No external monitor connected
    xrandr --output "$laptop_display" --auto
fi
