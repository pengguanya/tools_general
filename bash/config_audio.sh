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
speaker_sink="alsa_output.pci-0000_00_1f.3-platform-skl_hda_dsp_generic.HiFi__hw_sofhdadsp__sink"
headset_sink="alsa_output.usb-0b0e_Jabra_Link_380_50C275F5FAA5-00.iec958-stereo"
speaker_source="alsa_input.pci-0000_00_1f.3-platform-skl_hda_dsp_generic.HiFi__hw_sofhdadsp_6__source"
headset_source="alsa_input.usb-0b0e_Jabra_Link_380_50C275F5FAA5-00.mono-fallback"
speaker_port="[Out] Speaker"
headset_port="iec958-stereo-output"
microphone_port="[In] Mic1"
headset_microphone_port="analog-input-mic"

# Function to set sound output or input
set_sound() {
    local target="$1"
    local name="$2"
    local port="$3"
    
    if [ "$target" == "output" ]; then
        sink="$2"
        pactl set-default-sink "$sink"
        pactl set-sink-port "$sink" "$port"
    elif [ "$target" == "input" ]; then
        source="$2"
        pactl set-default-source "$source"
        pactl set-source-port "$source" "$port"
    else
        echo "Invalid target: $target"
        exit 1
    fi
}

# Set sound for speaker
set_speaker() {
    set_sound "output" "$speaker_sink" "$speaker_port"
    set_sound "input" "$speaker_source" "$microphone_port"
}

# Set sound for headset
set_headset() {
    set_sound "output" "$headset_sink" "$headset_port"
    set_sound "input" "$headset_source" "$headset_microphone_port"
}

# Usage information
usage() {
    echo "Usage: $0 [-s|-h]"
    echo "  -s: Set sound for speaker"
    echo "  -h: Set sound for headset"
    exit 1
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
