################################################################################
# Description:   Bash script to monitor a command's attribute and take action if the condition is met.
# Author:        Guanya Peng
# Date:          20230413
# Version:       1.0
# Usage:         bash kill_by_cond.sh
#
# This script monitors the specified command's attribute and takes action if
# the condition is met. It continuously checks the attribute of the command
# and kills the command's process if the condition is satisfied.
#
# Variables:
#   command    - The command to monitor
#   attribute  - The attribute to check
#   condition  - The condition to compare the attribute against
#
# Dependencies: bc, awk
#
################################################################################

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
