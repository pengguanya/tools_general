#!/bin/bash
#
# Script Name: leave_meet.sh
# Description: Schedule auto-leaving a Google Meet (Chrome) at a given time, even if its tab is in the background
# Usage: ./leave_meet.sh <meeting-code> <HH:MM[:SS]> [--date YYYY-MM-DD] | --list | --cancel <code> | --leave <code>
# Requirements: xdotool, systemd (user instance)
# Example: ./leave_meet.sh byo-sxyf-whp 14:29:30
#

set -euo pipefail

if [[ -t 1 ]]; then
    RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[0;33m' BLUE='\033[0;34m' NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' NC=''
fi

LOG="$HOME/.cache/leave-meet.log"
SELF="$(readlink -f "${BASH_SOURCE[0]}")"

log(){ echo "$(date '+%F %T'): $*" >> "$LOG"; }

show_help() {
    cat << 'EOF'
Usage: leave-meet <meeting-code> <HH:MM[:SS]> [--date YYYY-MM-DD]
       leave-meet --list
       leave-meet --cancel <meeting-code>

Schedule Chrome to leave a Google Meet at a given time by closing its tab.
The matching tab is found even when it is NOT the foreground tab (it walks
each Chrome window's tabs to locate "Meet - <meeting-code>").

Arguments:
  meeting-code   The Meet code in the URL, e.g. byo-sxyf-whp (meet.google.com/byo-sxyf-whp)
  HH:MM[:SS]     Local time to leave today (or on --date). Seconds optional.

Options:
  --date DATE    Schedule for a specific date (YYYY-MM-DD) instead of today.
  --list         List currently scheduled leave timers.
  --cancel CODE  Cancel the scheduled leave for a meeting code.
  -h, --help     Show this help.

Requirements: the machine must stay awake and logged in until the leave time.

Examples:
  leave-meet byo-sxyf-whp 14:29:30
  leave-meet abc-defg-hij 09:55 --date 2026-06-23
  leave-meet --list
  leave-meet --cancel byo-sxyf-whp
EOF
}

# ---- internal: actually leave the meeting (invoked by the systemd timer) ----
do_leave() {
    local code="$1"
    local pattern="Meet - ${code}"
    export DISPLAY="${DISPLAY:-:1}"
    export XAUTHORITY="${XAUTHORITY:-/run/user/$(id -u)/gdm/Xauthority}"

    # Fast path: Meet is the active tab of some window -> close directly.
    local win
    win=$(xdotool search --name "$pattern" 2>/dev/null | head -1 || true)
    if [[ -n "$win" ]]; then
        xdotool windowactivate --sync "$win" 2>>"$LOG" || true
        sleep 0.4
        xdotool key ctrl+w
        log "left meeting '$code' (fast path, window $win)"
        return 0
    fi

    # Fallback: walk every Chrome window's tabs to find the Meet tab.
    local w i t first
    for w in $(xdotool search --class google-chrome 2>/dev/null || true); do
        xdotool windowactivate --sync "$w" 2>>"$LOG" || true
        sleep 0.3
        xdotool key --clearmodifiers ctrl+1; sleep 0.35   # jump to first tab
        first=""
        for i in $(seq 1 25); do
            t=$(xdotool getwindowname "$w" 2>/dev/null || true)
            case "$t" in
                *"$pattern"*)
                    xdotool key ctrl+w
                    log "left meeting '$code' (tab walk, window $w, tab $i)"
                    return 0 ;;
            esac
            [[ "$i" -eq 1 ]] && first="$t"
            xdotool key --clearmodifiers ctrl+Next; sleep 0.35
            [[ "$i" -gt 1 && "$(xdotool getwindowname "$w" 2>/dev/null || true)" == "$first" ]] && break
        done
    done

    log "meeting '$code' tab not found in any Chrome window - nothing closed"
    return 0
}

# ---- internal: sanitize a meeting code into a systemd unit-safe token ----
unit_for() { printf 'leave-meet-%s' "$(printf '%s' "$1" | tr -c 'A-Za-z0-9-' '-')"; }

list_timers() {
    echo -e "${BLUE}● Scheduled leave timers:${NC}"
    systemctl --user list-timers --all --no-pager 'leave-meet-*' || true
}

cancel_one() {
    local code="$1" unit
    unit="$(unit_for "$code")"
    if systemctl --user stop "${unit}.timer" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Cancelled scheduled leave for '${code}'."
    else
        echo -e "${YELLOW}⚠${NC} No active leave timer found for '${code}'." >&2
    fi
}

schedule() {
    local code="$1" time="$2" date="${3:-}"
    command -v xdotool >/dev/null 2>&1 || { echo -e "${RED}✗ xdotool required${NC}" >&2; exit 1; }
    command -v systemd-run >/dev/null 2>&1 || { echo -e "${RED}✗ systemd-run required${NC}" >&2; exit 1; }

    # Compute target epoch.
    local target now
    now=$(date +%s)
    if [[ -n "$date" ]]; then
        target=$(date -d "$date $time" +%s) || { echo -e "${RED}✗ invalid date/time${NC}" >&2; exit 1; }
    else
        target=$(date -d "$time" +%s) || { echo -e "${RED}✗ invalid time${NC}" >&2; exit 1; }
        # If today's time already passed, roll to tomorrow.
        if [[ "$target" -le "$now" ]]; then
            target=$(date -d "tomorrow $time" +%s)
        fi
    fi

    local oncal unit
    oncal=$(date -d "@$target" '+%Y-%m-%d %H:%M:%S')
    unit="$(unit_for "$code")"

    # Replace any existing timer for this code.
    systemctl --user stop "${unit}.timer" 2>/dev/null || true

    systemd-run --user \
        --unit="$unit" \
        --on-calendar="$oncal" \
        --timer-property=AccuracySec=1s \
        --timer-property=RemainAfterElapse=no \
        --setenv=DISPLAY="${DISPLAY:-:1}" \
        --setenv=XAUTHORITY="${XAUTHORITY:-/run/user/$(id -u)/gdm/Xauthority}" \
        "$SELF" --leave "$code" >/dev/null

    echo -e "${GREEN}✓${NC} Will leave Meet '${BLUE}${code}${NC}' at ${BLUE}${oncal}${NC}."
    echo -e "  ${YELLOW}⚠${NC} Machine must stay awake & logged in until then."
    echo -e "  Log: $LOG   Cancel: leave-meet --cancel ${code}"
}

# ---------------------------- argument parsing ----------------------------
[[ $# -eq 0 ]] && { show_help; exit 0; }

case "$1" in
    -h|--help) show_help; exit 0 ;;
    --leave)   [[ $# -ge 2 ]] || { echo "need code" >&2; exit 1; }; do_leave "$2"; exit 0 ;;
    --list)    list_timers; exit 0 ;;
    --cancel)  [[ $# -ge 2 ]] || { echo -e "${RED}✗ --cancel needs a meeting code${NC}" >&2; exit 1; }; cancel_one "$2"; exit 0 ;;
esac

# Schedule mode: <code> <time> [--date DATE]
CODE=""; TIME=""; DATE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --date) DATE="$2"; shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        -*) echo -e "${RED}✗ Unknown option: $1${NC}" >&2; show_help >&2; exit 1 ;;
        *) if [[ -z "$CODE" ]]; then CODE="$1"; elif [[ -z "$TIME" ]]; then TIME="$1"; else
               echo -e "${RED}✗ Unexpected argument: $1${NC}" >&2; exit 1; fi; shift ;;
    esac
done

[[ -n "$CODE" && -n "$TIME" ]] || { echo -e "${RED}✗ Need <meeting-code> and <time>${NC}\n" >&2; show_help >&2; exit 1; }
schedule "$CODE" "$TIME" "$DATE"
