#!/bin/bash

terminal="alacritty --title vpn_term"

if [[ "$1" == "-d" || "$1" == "--debug" ]]; then
    LOGFILE="/tmp/opencon_$(date +%Y%m%d_%H%M%S).log"
    $terminal -e bash -c "opencon_core 2>&1 | tee '$LOGFILE'; echo '--- Exit code: '\$?' ---' | tee -a '$LOGFILE'; echo 'Press Enter to close...'; read"
    echo "Log saved to: $LOGFILE"
else
    $terminal -e opencon_core
fi
