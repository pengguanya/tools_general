################################################################################
# Description:   Bash script to monitor CPU usage of a command and kill the process if it exceeds the specified threshold.
# Author:        Guanya Peng
# Date:          20230413
# Version:       1.0
# Usage:         bash kill_by_cpu.sh
#
# This script continuously monitors the CPU usage of a specified command and
# kills the process if it exceeds the specified threshold. It retrieves the
# process IDs (PIDs) of the command, calculates the maximum CPU usage among
# those processes, and compares it to the threshold.
#
# Variables:
#   command    - The command to monitor
#   threshold  - The CPU usage threshold (in percentage)
#
# Dependencies: bc, awk, top
#
################################################################################

#!/bin/bash

command='/opt/fireeye/bin/xagt'   # Replace this with your command
threshold=60                    # Replace this with your threshold

while true; do
    pids=$(ps aux | grep "$command" | grep -v grep | awk '{print $2}')
    for pid in $pids; do
        cpu=$(top -bn1 -p $pid | tail -n1 | awk '{printf "%d", $9}')
        max_cpu=$(echo "$cpu 0" | tr ' ' '\n' | sort -nr | head -n1)
        echo $max_cpu
        if (( $(echo "$max_cpu > $threshold" | bc -l) )); then
            echo "CPU usage of $command with PID $pid is high: $max_cpu%"
            kill -9 $pid
        fi
    done
    sleep 1
done
