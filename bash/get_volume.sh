#!/bin/bash

################################################################################
# get_sink_info.sh - Script for retrieving volume percentage and mute status for
# the default audio sink in PulseAudio.
#
# This script provides the ability to check the volume percentage or mute status
# of the default audio sink (output device) in PulseAudio.
#
# Usage:
#   - To get the volume percentage: ./get_sink_info.sh volume
#   - To check if the sink is muted: ./get_sink_info.sh mute
#
# Author: Guanya Peng
# Date: Oct 13, 2023
################################################################################
to_proper_case() {
  local input="$1"
  echo "$input" | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2));}1'
}

# Function to get the default sink name
get_default_sink_name() {
    pactl get-default-sink
}

# Function to get the volume level of a specific sink
get_sink_volume() {
    local sink_name="$1"
    volume_info=$(pacmd list-sinks | grep -A 20 "name: <$sink_name>")
    volume_level=$(echo "$volume_info" | awk -F ' ' '/volume: front-left:/ {print $5}')
    echo "$volume_level"
}

# Function to check if the sink is muted
is_sink_muted() {
    local sink_name="$1"
    volume_info=$(pacmd list-sinks | grep -A 20 "name: <$sink_name>")
    mute_status=$(echo "$volume_info" | awk -F ' ' '/muted:/ {print $2}')
    echo $(to_proper_case "$mute_status")
}

# Get the default sink name
default_sink_name=$(get_default_sink_name)

if [ -z "$default_sink_name" ]; then
    echo "No default sink found."
    exit 1
fi

# Check for command-line arguments
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 [volume|mute]"
    exit 1
fi

# Process the command-line argument
case "$1" in
    volume)
        get_sink_volume "$default_sink_name"
        ;;
    mute)
        is_sink_muted "$default_sink_name"
        ;;
    *)
        echo "Invalid option: $1. Use 'volume' or 'mute'."
        exit 1
        ;;
esac

