#!/bin/bash

################################################################################
# configure_audio.sh - Script for configuring audio input and output settings.
#
# This script allows you to set audio input and output configurations for
# both speakers and headsets on your system.
#
# Usage: configure_audio.sh [-s|-h]
#   -s: Set sound for speaker
#   -h: Set sound for headset
#
# Author: Guanya Peng
# Date: October 13, 2023
################################################################################

# Define variables for sound configuration
speaker_sink="skl_hda_dsp_generic.HiFi__hw_sofhdadsp__sink"
headset_sink="Jabra_Link"
speaker_source="skl_hda_dsp_generic.HiFi__hw_sofhdadsp_6__source"
headset_source="Jabra_Link"

# Function to set sound output or input
set_sound() {
    local target="$1"
    local name="$2"
   
    # Fuzzy match the name with list of sinks/sources
    if [ "$target" == "output" ]; then
        sink=$(pactl list short sinks | grep "$name" | head -n 1 | cut -f 2)
        if [ -z "$sink" ]; then
            echo "No matching sink found for $name"
            exit 1
        fi
        pactl set-default-sink "$sink"
    elif [ "$target" == "input" ]; then
        source=$(pactl list short sources | grep "$name" | head -n 1 | cut -f 2)
        if [ -z "$source" ]; then
            echo "No matching source found for $name"
            exit 3
        fi
        pactl set-default-source "$source"
    else
        echo "Invalid target: $target"
        exit 2
    fi
}

# Set sound for speaker
set_speaker() {
    set_sound "output" "$speaker_sink"
    set_sound "input" "$speaker_source"
}

# Set sound for headset
set_headset() {
    set_sound "output" "$headset_sink"
    set_sound "input" "$headset_source"
}

# Usage information
usage() {
    echo "Usage: $0 [-s|-h]"
    echo "  -s: Set sound for speaker"
    echo "  -h: Set sound for headset"
    exit 4
}

# Check for the correct number of arguments
if [ $# -ne 1 ]; then
    usage
fi

valid_option=false

while getopts "sh" opt; do
    case "$opt" in
        s)
            set_speaker
            valid_option=true
            ;;

        h)
            set_headset
            valid_option=true
            ;;

        *)
            usage
            ;;
    esac
done

# If no valid option was provided, show usage
if [ "$valid_option" = false ]; then
    usage
fi
