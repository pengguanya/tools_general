#!/bin/bash
# Toggle between speaker and headset audio output

current=$(audiodev)

if [[ "$current" == "Speaker" ]]; then
    confaudio -h
elif [[ "$current" == "Headset" ]]; then
    confaudio -s
else
    # Default to speaker if unknown
    confaudio -s
fi
