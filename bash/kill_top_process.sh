#!/bin/bash

# Function to get top CPU-consuming processes
get_top_processes() {
  local top_processes=$(ps -eo pid,ppid,%cpu,%mem,cmd --sort=-%cpu --no-headers | head -n 10)
  echo "$top_processes"
}

# Function to kill a process by PID
kill_process_by_pid() {
  local pid=$1
  kill -9 "$pid"
}

# Function to kill top N processes
kill_top_processes() {
  local top_processes=$1

  while IFS= read -r line; do
    pid=$(echo "$line" | awk '{print $1}')
    kill_process_by_pid "$pid"
    echo "Process with PID $pid has been killed."
  done <<< "$top_processes"
}

# Get the top CPU-consuming processes
top_processes=$(get_top_processes)

# Print the processes as in top or htop with shortened commands
echo " PID    PPID    %CPU   %MEM   COMMAND"
echo "-------------------------------------"
while IFS= read -r line; do
  pid=$(echo "$line" | awk '{print $1}')
  ppid=$(echo "$line" | awk '{print $2}')
  cpu_usage=$(echo "$line" | awk '{print $3}')
  mem_usage=$(echo "$line" | awk '{print $4}')
  command=$(echo "$line" | awk '{for (i=5; i<=NF; i++) printf "%s ", $i; printf "\n"}' | awk '{print $1}')
  printf "%-7s %-7s %-6s %-6s %s\n" "$pid" "$ppid" "$cpu_usage" "$mem_usage" "$command"
done <<< "$top_processes"

# Prompt user for action
read -p "Enter 'p' to kill by PID, 'n' to kill top N processes, or 'q' to quit: " choice

if [[ "$choice" == "p" ]]; then
  # Prompt user to enter the PIDs to kill
  read -p "Enter the PIDs of the processes to kill (separated by spaces): " pids

  # Split the input into an array of PIDs
  read -ra pid_array <<< "$pids"

  # Loop through the PIDs and kill the corresponding processes
  for pid in "${pid_array[@]}"; do
    # Check if the input is a valid PID
    if [[ "$pid" =~ ^[0-9]+$ ]]; then
      # Confirm the action
      read -p "Are you sure you want to kill process with PID $pid? (y/n): " confirm

      if [[ "$confirm" == "y" ]]; then
        kill_process_by_pid "$pid"
        echo "Process with PID $pid has been killed."
      else
        echo "Process with PID $pid was not killed."
      fi
    else
      echo "Invalid PID: $pid. Skipping..."
    fi
  done
# ... previous code ...

elif [[ "$choice" == "n" ]]; then
  # Prompt user to enter the number of top processes to kill
  read -p "Enter the number of top processes to kill: " num_to_kill

  # Check if the input is a valid integer
  if [[ "$num_to_kill" =~ ^[0-9]+$ ]]; then
    # Get the specified number of top CPU-consuming processes
    top_processes_to_kill=$(head -n "$num_to_kill" <<< "$top_processes")

    # Display the top processes to be killed
    echo "Top $num_to_kill processes to be killed:"
    echo " PID     COMMAND"
    echo "-----------------"
    while IFS= read -r line; do
      pid=$(echo "$line" | awk '{print $1}')
      command=$(echo "$line" | awk '{for (i=5; i<=NF; i++) printf "%s ", $i; printf "\n"}' | awk '{print $1}')
      printf "%-8s %s\n" "$pid" "$command"
    done <<< "$top_processes_to_kill"

    # Confirm the action
    read -p "Are you sure you want to kill the above $num_to_kill processes? (y/n): " confirm

    if [[ "$confirm" == "y" ]]; then
      kill_top_processes "$top_processes_to_kill"
    else
      echo "No processes were killed."
    fi
  else
    echo "Invalid input. No processes were killed."
  fi
fi

