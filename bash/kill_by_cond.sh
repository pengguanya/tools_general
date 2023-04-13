#!/bin/bash

command='/opt/fireeye/bin/xagt'       # Replace this with your command
attribute='%cpu'                      # Replace this with the attribute to check
condition='> 90'                      # Replace this with the condition to check

while true; do
    pids=$(ps aux | grep "$command" | grep -v grep | awk '{print $2}')
    for pid in $pids; do
        value=$(ps -p $pid -o $attribute | awk 'NR>1')
        if (( $(echo "$value $condition" | bc -l) )); then
            echo "$attribute of $command with PID $pid is $condition: $value"
            kill -9 $pid
        fi
    done
    sleep 10
done
