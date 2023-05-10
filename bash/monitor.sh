#!/bin/bash

# Define the thresholds for fan speed, CPU temperature, and CPU usage
FAN_THRESHOLD=1200   # Adjust the value as per your fan specifications
TEMP_THRESHOLD=60    # Adjust the value as per your CPU temperature specifications
CPU_THRESHOLD=80.0   # Adjust the value as per your CPU usage specifications

# Function to send notification
send_notification() {
  local message=$1

  # Detect the desktop environment
  if [[ $XDG_SESSION_DESKTOP == *"ubuntu"* ]]; then
    # GNOME environment
    notify-send "System Monitor" "$message"
  elif [[ $XDG_SESSION_DESKTOP == *"awesome"* ]]; then
    # AwesomeWM environment
    awesome-client "naughty.notify({ title = 'System Monitor', text = '$message' })"
  fi
}

# Function to get top CPU-consuming processes
get_top_processes() {
  local processes=$(ps -eo pid,ppid,cmd,%cpu --sort=-%cpu --no-headers | head -n $TOP_PROCESSES)
  echo "$processes"
}

# Main script logic
while true; do
  # Get fan speed
  fan_speed=$(sensors | awk '/^fan1:/{print $2}' | tr -d 'RPM')

  # Get CPU temperature
  cpu_temp=$(sensors | awk '/^Tdie:/{print $2}' | tr -d '+°C')

  # Get CPU usage
  cpu_usage=$(mpstat 1 1 | awk '/^Average:/{print 100-$NF}')

  # Check if fan speed exceeds threshold
  if (( $(awk 'BEGIN { print '"$fan_speed"' > '"$FAN_THRESHOLD"' }') )); then
    send_notification "Fan speed is high! Current speed: $fan_speed RPM"
  fi

  # Check if CPU temperature exceeds threshold
  if (( $(awk 'BEGIN { print '"$cpu_temp"' > '"$TEMP_THRESHOLD"' }') )); then
    send_notification "CPU temperature is high! Current temperature: $cpu_temp°C"
  fi

  # Check if CPU usage exceeds threshold
  if (( $(awk 'BEGIN { print '"$cpu_usage"' > '"$CPU_THRESHOLD"' }') )); then
    top_processes=$(get_top_processes)
    message="CPU usage is high! Current usage: $cpu_usage%\n\nTop $TOP_PROCESSES processes:\n$top_processes"
    send_notification "$message"
  fi

  sleep 1  # Adjust the sleep duration as per your requirement
done
