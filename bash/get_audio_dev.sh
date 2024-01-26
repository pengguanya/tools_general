#!/bin/bash
################################################################################
# get_current_audio.sh - Script for identifying current audio input and output settings.
#
# This script identifies if the current audio input and output configurations
# of your system are for a specific speaker setup or headset.
#
# It compares the active input/output sink/source with predefined strings
# to determine if the active configuration matches the speaker or headset parameters.
#
# Usage: get_current_audio.sh
# NOTE: This script does not take any command line arguments.
#
# IMPORTANT: This script makes an assumption about the naming of your audio devices.
# Please note that if you change your headset or speaker setup for your system, 
# your device names may also change. In such cases, this script may fail to accurately 
# identify the current audio setup.
# The predefined strings in the script should be updated to reflect the new device
# names should this occur.
#
# Author: Guanya Peng 
# Date: January 26, 2024
################################################################################

# Define variables for sound configuration
speaker_sink="skl_hda_dsp_generic.HiFi__hw_sofhdadsp__sink"
headset_sink="Jabra_Link"
speaker_source="skl_hda_dsp_generic.HiFi__hw_sofhdadsp_6__source"
headset_source="Jabra_Link"

# Fetch the active sink and source names
active_sink=$(pactl info | grep 'Default Sink' | cut -d ' ' -f3)
active_source=$(pactl info | grep 'Default Source' | cut -d ' ' -f3)

# Check if they match our defined sinks/sources
if [[ $active_sink == *"$speaker_sink"* && $active_source == *"$speaker_source"* ]]; then
    echo "Speaker"
elif [[ $active_sink == *"$headset_sink"* && $active_source == *"$headset_source"* ]]; then
    echo "Headset"
else
    echo "Unknown Device"
fi
