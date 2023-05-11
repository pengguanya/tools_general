################################################################################
# Description:   Bash script to monitor and control CPU temperature.
# Author:        Guanya Peng
# Date:          20230511
# Version:       1.0
# Usage:         bash set_cpu_freq.sh
#
# This script monitors the CPU temperature and adjusts the CPU frequency based
# on temperature thresholds. It sets a maximum frequency limit for all CPU cores
# to control the temperature within safe limits.
#
# Temperature Thresholds:
#   - THRESHOLD_LOW: The lower temperature threshold (in Celsius)
#   - THRESHOLD_HIGH: The higher temperature threshold (in Celsius)
#
# CPU Frequency Limit:
#   - FREQ_LIMIT: The CPU frequency limit for all cores (in kHz)
#
# Dependencies: sensors
#
################################################################################

#!/bin/bash

# Temperature thresholds (in Celsius)
THRESHOLD_LOW=50
THRESHOLD_HIGH=80

# CPU frequency limit (in kHz) for all cores
FREQ_LIMIT=2300000

# Function to set CPU frequency for all cores
set_cpu_frequencies() {
  local freq_limit=$1
  for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq; do
    echo "$freq_limit" | sudo tee "$cpu" > /dev/null
  done
}

# Function to check if CPU frequencies have been reset
check_cpu_frequencies_reset() {
  local freq_limit=$1
  local cpu_frequencies=$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq)

  if [[ "$cpu_frequencies" == *"$freq_limit"* ]]; then
    return 0  # Frequencies have been reset
  else
    return 1  # Frequencies have not been reset
  fi
}

# Function to convert frequency value from kHz to GHz
convert_frequency_to_ghz() {
  local freq_khz=$1
  local freq_ghz=$(awk "BEGIN {print $freq_khz / 1000000}")
  printf "%.2f" "$freq_ghz"
}

# Function to monitor CPU temperature
monitor_cpu_temperature() {
  local cpu_temp=0
  while true; do
    cpu_temp=$(sensors | awk '/Core 0:/{print $3}' | cut -c 2-)
    cpu_temp=${cpu_temp%.*}  # Remove decimal values if present
    echo "Current CPU Temperature: $cpu_temp°C"

    if (( cpu_temp < THRESHOLD_LOW )); then
      set_cpu_frequencies "$FREQ_LIMIT"
      if check_cpu_frequencies_reset "$FREQ_LIMIT"; then
        freq_ghz=$(convert_frequency_to_ghz "$FREQ_LIMIT")
        echo "CPU frequencies have been reset to $freq_ghz GHz successfully."
        break
      else
        echo "Error: Failed to set CPU frequencies."
      fi
    elif (( cpu_temp >= THRESHOLD_LOW && cpu_temp < THRESHOLD_HIGH )); then
      set_cpu_frequencies "$FREQ_LIMIT"
      if check_cpu_frequencies_reset "$FREQ_LIMIT"; then
        freq_ghz=$(convert_frequency_to_ghz "$FREQ_LIMIT")
        echo "CPU frequencies have been reset to $freq_ghz GHz successfully."
        break
      else
        echo "Error: Failed to set CPU frequencies."
      fi
    else
      set_cpu_frequencies "$FREQ_LIMIT"
      if check_cpu_frequencies_reset "$FREQ_LIMIT"; then
        freq_ghz=$(convert_frequency_to_ghz "$FREQ_LIMIT")
        echo "CPU frequencies have been reset to $freq_ghz GHz successfully."
      else
        echo "Error: Failed to set CPU frequencies."
      fi
      echo "Warning: CPU temperature is too high!"
      # You can add additional actions here, such as sending notifications or taking preventive measures.
    fi

    sleep 1
  done
}

# Start monitoring CPU temperature
monitor_cpu_temperature
