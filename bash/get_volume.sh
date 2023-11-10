#!/bin/bash

################################################################################
# get_sink_info.sh - Script for retrieving volume percentage and mute status for
# the default audio sink in PulseAudio.
#
# This script provides the ability to check the volume percentage or mute status
# of the default audio sink (output device) in PulseAudio.
#
# Usage:
#   - To get the volume percentage: ./get_sink_info.sh -t 3 -o volume
#   - To check if the sink is muted: ./get_sink_info.sh -t 3 -o mute
#
# Author: Guanya Peng
# Date: Oct 13, 2023
################################################################################

to_proper_case() {
  local input="$1"
  echo "$input" | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2));}1'
}

# Function to format the output with a specified width
format_output() {
    local value="$1"
    printf "%*s" "$width" "$value"  # Right-aligned, width specified by -t option
}

# Function to get the volume level of a specific sink
get_sink_volume() {
    local sink_name="$1"
    volume_info=$(pactl get-sink-volume "$sink_name")
    volume_level=$(echo "$volume_info" | awk 'tolower($0) ~ /volume:/ {print $5}')
    format_output "$volume_level"
}

# Function to check if the sink is muted
is_sink_muted() {
    local sink_name="$1"
    mute_status=$(pactl get-sink-mute "$sink_name" | awk '{print $2}')
    format_output "$(to_proper_case "$mute_status")"
}

# Set default values
width=3
output_type=""

# Parse command-line options
while getopts ":t:o:" opt; do
    case $opt in
        t)
            width="$OPTARG"
            ;;
        o)
            output_type="$OPTARG"
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            exit 1
            ;;
        :)
            echo "Option -$OPTARG requires an argument." >&2
            exit 1
            ;;
    esac
done

# Shift the options so that the positional parameters are not affected
shift $((OPTIND - 1))

# Get the default sink name
default_sink_name="@DEFAULT_SINK@"

if [ -z "$default_sink_name" ]; then
    echo "No default sink found."
    exit 1
fi

# Check for required options
if [ -z "$output_type" ]; then
    echo "Usage: $0 -t <width> -o [volume|mute]"
    exit 1
fi

# Process the output type
case "$output_type" in
    volume)
        get_sink_volume "$default_sink_name"
        ;;
    mute)
        is_sink_muted "$default_sink_name"
        ;;
    *)
        echo "Invalid option: $output_type. Use 'volume' or 'mute'."
        exit 1
        ;;
esac
