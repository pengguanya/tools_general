#!/bin/bash

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
