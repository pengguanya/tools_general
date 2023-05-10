#!/bin/bash

# Define the thresholds for fan speed, CPU temperature, and CPU usage
FAN_THRESHOLD=2000  # Adjust the value as per your fan specifications
TEMP_THRESHOLD=80   # Adjust the value as per your CPU temperature specifications
CPU_THRESHOLD=90    # Adjust the value as per your CPU usage specifications

# Function to send notification
send_notification() {
  local message=$1
  echo "$message"  # Replace this line with the code to send the notification
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
  if (( fan_speed > FAN_THRESHOLD )); then
    send_notification "Fan speed is high! Current speed: $fan_speed RPM"
  fi

  # Check if CPU temperature exceeds threshold
  if (( cpu_temp > TEMP_THRESHOLD )); then
    send_notification "CPU temperature is high! Current temperature: $cpu_temp°C"
  fi

  # Check if CPU usage exceeds threshold
  if (( cpu_usage > CPU_THRESHOLD )); then
    send_notification "CPU usage is high! Current usage: $cpu_usage%"
  fi

  sleep 1  # Adjust the sleep duration as per your requirement
done

