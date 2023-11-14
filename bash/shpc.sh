#!/bin/bash

protocal=cifs
username="$USER"
domain="emea.roche.com"
endpoint="exports.hps.kau.science.roche.com/home"
mount_point="/home/pengg3/remote/shpc"

sudo mount -t cifs -o username="$username",domain="$domain" //"$endpoint" "$mount_point"
