#!/bin/bash
#
# Script Name: genpass.sh
# Description: Generate strong passwords with optional clipboard copy and storage in pass/Bitwarden
# Usage: genpass [-l N] [--min N --max N] [-c] [-p PATH] [-b NAME] [--no-symbols] [-h]
# Requirements: python3; optional: xclip (-c), pass (-p), bw + jq (-b)
# Example: genpass -l 24 -c -p Work/GitHub/token
#

set -euo pipefail

# --- Defaults ---
DEFAULT_LENGTH=20
BOUNDS_MIN=8
BOUNDS_MAX=128
DEFAULT_SYMBOLS='"%&'"'"'()*+,-./:;<=>?!'
CLIP_TIMEOUT=45
BW_PASS_ENTRY="Personal/Bitwarden/vault.bitwarden.com/guanya.peng24@gmail.com"

# --- State ---
LENGTH=""
MIN_LENGTH_ARG=""
MAX_LENGTH_ARG=""
USE_SYMBOLS=true
CUSTOM_SYMBOLS=""
CLIP=false
PASS_PATH=""
BW_NAME=""
BW_SESSION=""

# --- Colors (only when stdout is a terminal) ---
if [[ -t 2 ]]; then
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    NC='\033[0m'
else
    GREEN='' YELLOW='' RED='' NC=''
fi

die() { echo -e "${RED}Error: $1${NC}" >&2; exit 1; }
warn() { echo -e "${YELLOW}Warning: $1${NC}" >&2; }
info() { echo -e "${GREEN}$1${NC}" >&2; }

# --- Help ---
show_help() {
    cat << 'EOF'
Usage: genpass [OPTIONS]

Generate a strong random password using Python's secrets module.

Options:
  -l, --length N       Exact password length (default: 20)
  --min N              Minimum length for random range (use with --max)
  --max N              Maximum length for random range (use with --min)
  --no-symbols         Alphanumeric only (no special characters)
  --symbols CHARS      Custom symbol set (default: "%&'()*+,-./:;<=>?!)
  -c, --clip           Copy to clipboard, auto-clear after 45s, suppress stdout
  -p, --pass PATH      Store in pass at PATH (e.g., Work/GitHub/token)
  -b, --bitwarden NAME Store/update as login item NAME in Bitwarden
  -h, --help           Show this help

Notes:
  -l and --min/--max are mutually exclusive.
  When both -p and -b are given, stores in both (pass first, then Bitwarden).
  Password is only printed to stdout when -c is not used.

Examples:
  genpass                          # 20-char password to stdout
  genpass -l 30                    # 30-char password
  genpass --min 15 --max 25        # Random length 15-25
  genpass --no-symbols             # Alphanumeric only
  genpass -c                       # Copy to clipboard, clear after 45s
  genpass -p Work/GitHub/token     # Generate and store in pass
  genpass -b "GitHub Token"        # Generate and store in Bitwarden
  genpass -c -p Work/API -b API    # Copy + store in both
EOF
}

# --- Password generation (inline Python) ---
generate_password() {
    local length="$1"
    local symbols="$2"

    python3 -c "
import secrets, string, sys

length = int(sys.argv[1])
symbols = sys.argv[2]

upper = string.ascii_uppercase
lower = string.ascii_lowercase
digits = string.digits

bad_first = set('?!')
first_symbols = ''.join(c for c in symbols if c not in bad_first)

first_pool = upper + lower + digits + first_symbols
rest_pool = upper + lower + digits + symbols

for _ in range(1000):
    pw = secrets.choice(first_pool) + ''.join(secrets.choice(rest_pool) for _ in range(length - 1))
    has_upper = any(c in upper for c in pw)
    has_lower = any(c in lower for c in pw)
    has_digit = any(c in digits for c in pw)
    has_symbol = (not symbols) or any(c in symbols for c in pw)
    if has_upper and has_lower and has_digit and has_symbol:
        print(pw)
        sys.exit(0)

print('Failed to generate valid password after 1000 attempts', file=sys.stderr)
sys.exit(1)
" "$length" "$symbols"
}

# --- Clipboard ---
copy_to_clipboard() {
    local password="$1"
    echo -n "$password" | xclip -selection clipboard
    echo -n "$password" | xclip -selection primary
    (
        sleep "$CLIP_TIMEOUT"
        echo -n "" | xclip -selection clipboard 2>/dev/null
        echo -n "" | xclip -selection primary 2>/dev/null
    ) &
    disown
    info "Copied to clipboard. Clearing in ${CLIP_TIMEOUT}s."
}

# --- Bitwarden session management ---
ensure_bw_session() {
    # Check login status
    if ! bw login --check &>/dev/null; then
        warn "Not logged in to Bitwarden."
        if [[ -f "$HOME/bitwarden_tokens.txt" ]]; then
            info "Logging in with API key from ~/bitwarden_tokens.txt..."
            local client_id client_secret
            client_id=$(grep -A1 "client_id:" "$HOME/bitwarden_tokens.txt" | tail -1 | tr -d ' ')
            client_secret=$(grep -A1 "client_secret:" "$HOME/bitwarden_tokens.txt" | tail -1 | tr -d ' ')
            if [[ -n "$client_id" && -n "$client_secret" ]]; then
                BW_CLIENTID="$client_id" BW_CLIENTSECRET="$client_secret" bw login --apikey
            else
                die "Could not parse API credentials from ~/bitwarden_tokens.txt"
            fi
        else
            die "Not logged in. Run: bw login --apikey"
        fi
    fi

    # Unlock vault with master password from pass
    local master_pw
    master_pw=$(pass show "$BW_PASS_ENTRY" 2>/dev/null | head -1 || true)
    [[ -z "$master_pw" ]] && die "Could not retrieve Bitwarden master password from pass"

    BW_SESSION=$(printf "%s\n" "$master_pw" | bw unlock --raw 2>&1 | tail -1)
    if [[ -z "$BW_SESSION" || ${#BW_SESSION} -lt 20 ]]; then
        die "Failed to unlock Bitwarden vault"
    fi
    export BW_SESSION
    info "Bitwarden vault unlocked."
}

# --- Store in pass ---
store_in_pass() {
    local pass_path="$1"
    local password="$2"
    printf '%s\n' "$password" | pass insert -f -m "$pass_path" >/dev/null
    info "Stored in pass: $pass_path"
}

# --- Store in Bitwarden ---
store_in_bitwarden() {
    local item_name="$1"
    local password="$2"

    # Search for existing item
    local existing_id
    existing_id=$(bw list items --search "$item_name" 2>/dev/null | jq -r '.[0].id // empty')

    if [[ -n "$existing_id" ]]; then
        # Update existing item
        local item_json
        item_json=$(bw get item "$existing_id")
        item_json=$(echo "$item_json" | jq --arg pw "$password" '.login.password = $pw')
        echo "$item_json" | bw encode | bw edit item "$existing_id" >/dev/null
        info "Updated Bitwarden item: $item_name"
    else
        # Create new login item
        local new_item
        new_item=$(jq -n \
            --arg name "$item_name" \
            --arg pw "$password" \
            '{
                organizationId: null,
                type: 1,
                name: $name,
                login: {
                    uris: [],
                    username: null,
                    password: $pw
                },
                reprompt: 0
            }')
        echo "$new_item" | bw encode | bw create item >/dev/null
        info "Created Bitwarden item: $item_name"
    fi
}

# --- Cleanup ---
cleanup() {
    if [[ -n "${BW_SESSION:-}" ]]; then
        bw lock &>/dev/null || true
        info "Bitwarden vault locked."
    fi
}
trap cleanup EXIT

# --- Argument parsing ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -l|--length)    LENGTH="$2"; shift ;;
        --min)          MIN_LENGTH_ARG="$2"; shift ;;
        --max)          MAX_LENGTH_ARG="$2"; shift ;;
        -c|--clip)      CLIP=true ;;
        -p|--pass)      PASS_PATH="$2"; shift ;;
        -b|--bitwarden) BW_NAME="$2"; shift ;;
        --no-symbols)   USE_SYMBOLS=false ;;
        --symbols)      CUSTOM_SYMBOLS="$2"; USE_SYMBOLS=true; shift ;;
        -h|--help)      show_help; exit 0 ;;
        *)              die "Unknown option: $1. Use -h for help." ;;
    esac
    shift
done

# --- Validate arguments ---
if [[ -n "$LENGTH" && (-n "$MIN_LENGTH_ARG" || -n "$MAX_LENGTH_ARG") ]]; then
    die "-l and --min/--max are mutually exclusive"
fi

if [[ -n "$MIN_LENGTH_ARG" && -z "$MAX_LENGTH_ARG" ]] || [[ -z "$MIN_LENGTH_ARG" && -n "$MAX_LENGTH_ARG" ]]; then
    die "--min and --max must be used together"
fi

# Resolve final length
if [[ -n "$LENGTH" ]]; then
    [[ "$LENGTH" -ge "$BOUNDS_MIN" && "$LENGTH" -le "$BOUNDS_MAX" ]] 2>/dev/null \
        || die "Length must be between $BOUNDS_MIN and $BOUNDS_MAX"
    final_length="$LENGTH"
elif [[ -n "$MIN_LENGTH_ARG" ]]; then
    [[ "$MIN_LENGTH_ARG" -ge "$BOUNDS_MIN" ]] 2>/dev/null || die "Min length must be >= $BOUNDS_MIN"
    [[ "$MAX_LENGTH_ARG" -le "$BOUNDS_MAX" ]] 2>/dev/null || die "Max length must be <= $BOUNDS_MAX"
    [[ "$MIN_LENGTH_ARG" -le "$MAX_LENGTH_ARG" ]] 2>/dev/null || die "--min must be <= --max"
    final_length=$(python3 -c "import secrets; print(secrets.choice(range($MIN_LENGTH_ARG, $MAX_LENGTH_ARG + 1)))")
else
    final_length="$DEFAULT_LENGTH"
fi

# Resolve symbol set
if [[ "$USE_SYMBOLS" == true ]]; then
    symbols="${CUSTOM_SYMBOLS:-$DEFAULT_SYMBOLS}"
else
    symbols=""
fi

# --- Dependency checks (conditional) ---
command -v python3 &>/dev/null || die "python3 is required"
[[ "$CLIP" == true ]] && ! command -v xclip &>/dev/null && die "xclip required for -c (install: sudo apt install xclip)"
[[ -n "$PASS_PATH" ]] && ! command -v pass &>/dev/null && die "pass required for -p (install: sudo apt install pass)"
if [[ -n "$BW_NAME" ]]; then
    command -v bw &>/dev/null || die "bw (Bitwarden CLI) required for -b"
    command -v jq &>/dev/null || die "jq required for -b (install: sudo apt install jq)"
fi

# --- Main ---
password=$(generate_password "$final_length" "$symbols")

# Store in pass
if [[ -n "$PASS_PATH" ]]; then
    store_in_pass "$PASS_PATH" "$password" || warn "Failed to store in pass"
fi

# Store in Bitwarden
if [[ -n "$BW_NAME" ]]; then
    ensure_bw_session
    store_in_bitwarden "$BW_NAME" "$password" || warn "Failed to store in Bitwarden"
fi

# Clipboard or stdout
if [[ "$CLIP" == true ]]; then
    copy_to_clipboard "$password"
else
    echo "$password"
fi
