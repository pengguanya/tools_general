#!/bin/bash

# OpenConnect VPN client for Roche GlobalProtect with SAML authentication
#
# Uses gp-saml-gui to handle SAML SSO login in a browser window,
# then connects via OpenConnect with the obtained auth cookie.
#
# Usage: opencon_core [-a]
#   -a: Select an authgroup interactively (bypasses gp-saml-gui)

# Default authgroup and gateway
DEFAULT_AUTHGROUP="Basel"
AUTHGROUP=$DEFAULT_AUTHGROUP
INTERACTIVE_MODE=false

# Gateway mapping (authgroup -> gateway hostname)
declare -A GATEWAYS=(
    ["Mannheim"]="gwgp_mah.roche.net"
    ["Buenos_Aires"]="gwgp_rbu.roche.net"
    ["Shanghai"]="gwgp_rgw.roche.net"
    ["Indianapolis"]="gwgp_ind.roche.net"
    ["Basel"]="gwgp_rmu.roche.net"
    ["Illovo"]="gwgp_rll.roche.net"
    ["Mexico"]="gwgp_rmx.roche.net"
    ["Sao_Paulo"]="gwgp_rso.roche.net"
    ["Sydney"]="gwgp_rsy.roche.net"
    ["Tokyo"]="gwgp_rt5.roche.net"
    ["Santa_Clara"]="gwgp_sc1.roche.net"
    ["Singapore"]="gwgp_shp.roche.net"
)

# Paths and options
OPENCONNECT_PATH="/usr/sbin/openconnect"
GP_SAML_GUI="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)/gp_saml_gui.py"
PROTOCOL="gp"
OS="linux"
CERT_PATH="/home/$USER/.config/rlcaas-roche/$USER.pem"
KEY_PATH="/home/$USER/.config/rlcaas-roche/$USER.key"
USER_OPTION="$USER"
CSD_USER="$USER"
CSD_WRAPPER="/usr/libexec/openconnect/hipreport.sh"
PORTAL="portalgp.roche.net"

# Function to display usage
usage() {
    echo "Usage: $0 [-a]"
    echo "  -a: Select an authgroup interactively (bypass SAML GUI)"
    exit 1
}

# Function to connect via gp-saml-gui (handles SAML browser login)
execute_saml_openconnect() {
    # Resolve gateway hostname from authgroup
    local gateway="${GATEWAYS[$AUTHGROUP]}"
    if [[ -z "$gateway" ]]; then
        echo "ERROR: Unknown authgroup '$AUTHGROUP'. Available:"
        printf '  %s\n' "${!GATEWAYS[@]}"
        exit 1
    fi

    echo "Launching SAML authentication browser window..."
    echo "  Gateway: $AUTHGROUP ($gateway)"
    echo "Complete the login in the browser to proceed."

    # Step 1: Run gp-saml-gui against the GATEWAY directly (not portal).
    # Authenticating against the gateway avoids the portal-to-gateway redirect
    # issue where OpenConnect reads the prelogin-cookie from stdin twice (once
    # for portal, once for gateway) but the portal cookie is not valid for the
    # gateway (auth-failed-password-empty).
    # See: https://gitlab.com/openconnect/openconnect/-/issues/147
    local saml_output
    saml_output=$(/usr/bin/python3 "$GP_SAML_GUI" "$gateway" --gateway \
        -c "$CERT_PATH" \
        --key "$KEY_PATH" \
        --clientos Linux)

    if [[ $? -ne 0 || -z "$saml_output" ]]; then
        echo "ERROR: SAML authentication failed or was cancelled."
        exit 1
    fi

    # Step 2: Parse output variables
    # gp-saml-gui outputs: HOST='https://server/gateway:cookie-name'
    #                       USER='username'  COOKIE='value'  OS='linux-64'
    local SAML_HOST SAML_USER SAML_COOKIE SAML_OS
    SAML_HOST=$(echo "$saml_output" | grep "^HOST=" | cut -d= -f2- | tr -d "'")
    SAML_USER=$(echo "$saml_output" | grep "^USER=" | cut -d= -f2- | tr -d "'")
    SAML_COOKIE=$(echo "$saml_output" | grep "^COOKIE=" | cut -d= -f2- | tr -d "'")
    SAML_OS=$(echo "$saml_output" | grep "^OS=" | cut -d= -f2- | tr -d "'")

    if [[ -z "$SAML_COOKIE" || -z "$SAML_HOST" ]]; then
        echo "ERROR: Failed to obtain SAML cookie from browser login."
        echo "Output was: $saml_output"
        exit 1
    fi

    # Extract server and usergroup path from HOST URL
    # HOST is like: https://server/gateway:prelogin-cookie
    local server usergroup
    server=$(echo "$SAML_HOST" | sed 's|https://||' | cut -d/ -f1)
    usergroup=$(echo "$SAML_HOST" | sed 's|https://[^/]*/||')

    echo "SAML authentication successful. Connecting to VPN..."
    echo "  Server: $server"
    echo "  User: $SAML_USER"

    # Step 3: Connect with OpenConnect using the SAML cookie
    echo "$SAML_COOKIE" | sudo "$OPENCONNECT_PATH" \
        --protocol="$PROTOCOL" \
        --user="$SAML_USER" \
        --os="${SAML_OS:-$OS}" \
        --usergroup="$usergroup" \
        --passwd-on-stdin \
        -c "$CERT_PATH" \
        -k "$KEY_PATH" \
        --csd-user="$CSD_USER" \
        --csd-wrapper="$CSD_WRAPPER" \
        "$server"
}

# Function to connect interactively (fallback, no SAML GUI)
execute_openconnect_interactive() {
    sudo "$OPENCONNECT_PATH" --protocol="$PROTOCOL" --os="$OS" \
        -c "$CERT_PATH" -k "$KEY_PATH" -u "$USER_OPTION" \
        --csd-user="$CSD_USER" \
        --csd-wrapper="$CSD_WRAPPER" \
        "$PORTAL"
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

# Execute VPN login
if $INTERACTIVE_MODE; then
    execute_openconnect_interactive
else
    execute_saml_openconnect
fi
