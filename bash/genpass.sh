#!/bin/bash
#
# Script Name: genpass.sh
# Description: Generates a single strong password (15–50 chars) with required
#              digit, upper, lower, and punctuation characters while avoiding
#              leading punctuation that commonly breaks shells.
# Usage: ./genpass.sh
# Requirements: pwgen, grep
# Example: ./genpass.sh > ~/tmp/new-password.txt
#
# Generate a password using pwgen with at least 1 digit, 1 uppercase letter, and 1 lowercase letter
# Length between 15 and 50 characters
while true; do
    PASSWORD=$(pwgen -1 -c -n 50 1)
    
    # Check password against the specified rules
    if [[ ${#PASSWORD} -ge 15 && ${#PASSWORD} -le 50 ]] && 
       echo "$PASSWORD" | grep -q '[0-9]' && 
       echo "$PASSWORD" | grep -q '[A-Z]' && 
       echo "$PASSWORD" | grep -q '[a-z]' && 
       echo "$PASSWORD" | grep -q '[%&'"'"'()*+,-./:;<=>?]' && 
       [[ ! $PASSWORD =~ ^[?!] ]]; then
        break
    fi
done

# Print the password
echo $PASSWORD
