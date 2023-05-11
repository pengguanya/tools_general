#!/bin/bash

# Define the thresholds for CPU temperature and CPU usage
TEMP_THRESHOLD=80.0  # Adjust the value as per your CPU temperature specifications
CPU_THRESHOLD=90.0   # Adjust the value as per your CPU usage specifications
TOP_PROCESSES=3      # Adjust the value to set the number of top processes to display

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
  # Get CPU temperature
  cpu_temp=$(sensors | awk '/^Package id 0:/{print $4}' | tr -d '+°C')

  # Get CPU usage
  cpu_usage=$(mpstat 1 1 | awk '/^Average:/{print 100-$NF}')

  # Check if CPU temperature exceeds threshold
  if (( $(echo "$cpu_temp > $TEMP_THRESHOLD" | bc -l) )); then
    top_processes=$(get_top_processes)
    message="CPU temperature is high! Current temperature: $cpu_temp°C\n\nTop $TOP_PROCESSES processes:\n$top_processes"
    send_notification "$message"
  fi

  # Check if CPU usage exceeds threshold
  if (( $(echo "$cpu_usage > $CPU_THRESHOLD" | bc -l) )); then
    top_processes=$(get_top_processes)
    message="CPU usage is high! Current temperature: $cpu_temp°C\n\nTop $TOP_PROCESSES processes:\n$top_processes"
    send_notification "$message"
  fi

  sleep 1  # Adjust the sleep duration as per your requirement
done

