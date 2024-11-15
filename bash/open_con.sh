#!/bin/bash

# Default authgroup
DEFAULT_AUTHGROUP="Basel"
AUTHGROUP=$DEFAULT_AUTHGROUP
INTERACTIVE_MODE=false

# Paths and options
OPENCONNECT_PATH="/usr/sbin/openconnect"
PROTOCOL="gp"
OS="linux"
CERT_PATH="/home/$USER/.config/rlcaas-roche/$USER.pem"
KEY_PATH="/home/$USER/.config/rlcaas-roche/$USER.key"
USER_OPTION="$USER"
CSD_USER="$USER"
CSD_WRAPPER="/usr/libexec/openconnect/hipreport.sh"
PORTAL="portalgp.roche.net"

# Fetch password from pass
PASSWORD=$(pass show Work/Roche/$USER)

# Function to display usage
usage() {
    echo "Usage: $0 [-a]"
    echo "  -a: Select an authgroup interactively"
    exit 1
}

# Function to execute openconnect command
execute_openconnect() {
    local authgroup=$1
    local cmd="sudo $OPENCONNECT_PATH --protocol=$PROTOCOL --os=$OS \
        -c $CERT_PATH -k $KEY_PATH -u $USER_OPTION --csd-user=$CSD_USER \
        --csd-wrapper=$CSD_WRAPPER $PORTAL"

    if ! $INTERACTIVE_MODE; then
        cmd="$cmd --authgroup=$authgroup --passwd-on-stdin"
        echo "$PASSWORD" | $cmd
    else
        $cmd
    fi
}

# Parse options
while getopts ":a" opt; do
    case ${opt} in
        a )
            INTERACTIVE_MODE=true
            ;;
        \? )
            usage
            ;;
    esac
done

# Execute VPN login command
execute_openconnect $AUTHGROUP
