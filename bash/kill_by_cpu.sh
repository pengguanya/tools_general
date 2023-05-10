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
