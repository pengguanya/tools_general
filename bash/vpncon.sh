#!/bin/bash
#
# Script Name: vpncon.sh
# Description: VPN connection dispatcher — launches the active VPN method
#              in an Alacritty terminal. Methods are self-contained scripts
#              in ~/.config/vpn/methods.d/, each encapsulating its own
#              command, arguments, and environment setup.
# Usage: vpncon [OPTIONS]
#        vpncon --list | --set <method> | --current
# Requirements: alacritty
# Example: vpncon                # launch active method
#          vpncon --set rochevpn # switch to rochevpn
#

CONFIG_DIR="$HOME/.config/vpn"
ACTIVE_FILE="$CONFIG_DIR/active"
METHODS_DIR="$CONFIG_DIR/methods.d"
TERMINAL="alacritty --title vpn_term"

get_active_method() {
    if [[ -f "$ACTIVE_FILE" ]]; then
        head -1 "$ACTIVE_FILE" | tr -d ' \t\r'
    else
        echo ""
    fi
}

get_description() {
    local script="$1"
    grep -m1 '^# Description:' "$script" 2>/dev/null | sed 's/^# Description: *//'
}

show_help() {
    cat <<EOF
Usage: vpncon [OPTIONS]

VPN connection dispatcher. Launches the active VPN method in a terminal.

Options:
  (none)            Launch VPN with the active method
  -l, --list        List registered methods (active marked with *)
  -s, --set METHOD  Switch active method
  -c, --current     Print current active method
  -d, --debug       Launch with debug logging to /tmp/vpncon_*.log
  -h, --help        Show this help

Config:
  $METHODS_DIR/   One executable script per method
  $ACTIVE_FILE              Active method name

Adding a new method:
  1. Create a script in $METHODS_DIR/mymethod:
       #!/bin/bash
       # Description: What this method does
       exec mycommand --with --args
  2. chmod +x $METHODS_DIR/mymethod
  3. vpncon --set mymethod
EOF
}

list_methods() {
    if [[ ! -d "$METHODS_DIR" ]] || [[ -z "$(ls -A "$METHODS_DIR" 2>/dev/null)" ]]; then
        echo "No methods found in $METHODS_DIR"
        exit 1
    fi
    local active
    active=$(get_active_method)
    for script in "$METHODS_DIR"/*; do
        [[ ! -f "$script" ]] && continue
        local name desc marker
        name=$(basename "$script")
        desc=$(get_description "$script")
        if [[ "$name" == "$active" ]]; then
            marker="*"
        else
            marker=" "
        fi
        printf "%s %-20s %s\n" "$marker" "$name" "$desc"
    done
}

set_method() {
    local method="$1"
    if [[ -z "$method" ]]; then
        echo "Usage: vpncon --set <method>"
        exit 1
    fi
    if [[ ! -x "$METHODS_DIR/$method" ]]; then
        echo "Error: method '$method' not found in $METHODS_DIR"
        echo "Available methods:"
        list_methods
        exit 1
    fi
    mkdir -p "$CONFIG_DIR"
    echo "$method" > "$ACTIVE_FILE"
    echo "Active VPN method set to: $method"
}

launch_vpn() {
    local method debug="$1"
    method=$(get_active_method)
    if [[ -z "$method" ]]; then
        echo "No active method set. Run 'vpncon --set <method>' first."
        echo "Available methods:"
        list_methods
        exit 1
    fi
    local script="$METHODS_DIR/$method"
    if [[ ! -x "$script" ]]; then
        echo "Error: method script '$script' not found or not executable"
        echo "Available methods:"
        list_methods
        exit 1
    fi
    if [[ "$debug" == "debug" ]]; then
        LOGFILE="/tmp/vpncon_$(date +%Y%m%d_%H%M%S).log"
        $TERMINAL -e bash -c "'$script' 2>&1 | tee '$LOGFILE'; echo '--- Exit code: '\$?' ---' | tee -a '$LOGFILE'; echo 'Press Enter to close...'; read"
        echo "Log saved to: $LOGFILE"
    else
        $TERMINAL -e "$script"
    fi
}

case "${1:-}" in
    -h|--help)
        show_help
        ;;
    -l|--list)
        list_methods
        ;;
    -s|--set)
        set_method "$2"
        ;;
    -c|--current)
        get_active_method
        ;;
    -d|--debug)
        launch_vpn debug
        ;;
    "")
        launch_vpn
        ;;
    *)
        echo "Unknown option: $1"
        echo "Run 'vpncon --help' for usage"
        exit 1
        ;;
esac
