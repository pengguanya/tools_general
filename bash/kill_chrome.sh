#!/bin/bash

# Script to kill all Google Chrome processes

echo "Terminating all Google Chrome processes..."

# Using pkill to terminate all processes with 'chrome' in their name
pkill -f chrome

echo "All Google Chrome processes have been terminated."
