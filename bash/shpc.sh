#!/bin/bash
#
# Script Name: shpc.sh
# Description: Mounts the Roche SHPC CIFS share onto a local mount point using
#              credentials stored in /etc/.cifs.cred, creating the mount point
#              when necessary.
# Usage: sudo ./shpc.sh
# Requirements: CIFS-utils, valid `/etc/.cifs.cred`, sudo rights
# Example: sudo ./shpc.sh && ls /home/pengg3/test
#
protocal=cifs
username="$USER"
domain="emea.roche.com"
endpoint="exports.hps.kau.science.roche.com/home"
mount_point="/home/pengg3/test"
mkdir -p "$mount_point"

#sudo mount -t cifs -o username="$username",domain="$domain" //"$endpoint" "$mount_point"
sudo mount -t cifs -o domain="$domain",credentials="/etc/.cifs.cred" //"$endpoint" "$mount_point"
