#!/bin/bash

# Check if PulseAudio is running
if ! pactl info &>/dev/null; then
  echo "Error: PulseAudio is not running." >&2
  exit 1
fi

# Toggle the mute status of the default audio sink
pactl set-sink-mute @DEFAULT_SINK@ toggle
