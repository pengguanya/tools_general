#!/bin/bash
#
# Script Name: localhost.sh
# Description: Convenience launcher for local Rails or Jekyll servers that
#              auto-kills conflicting processes and exposes common flags.
# Usage: ./localhost.sh [--framework jekyll|rails] [--host HOST] [--port PORT] [--draft]
# Requirements: lsof, bundle, target framework gems
# Example: ./localhost.sh --framework jekyll --host 0.0.0.0 --port 8080 --draft
#
# Default values
HOST="127.0.0.1"
PORT=4000
DRAFT=false
FRAMEWORK="jekyll"
show_help_after_run=false

# Function: Show help
show_help() {
    echo ""
    echo "USAGE: $0 [OPTIONS]"
    echo ""
    echo "Starts a local server using the specified framework (default: jekyll)."
    echo ""
    echo "Options:"
    echo "  --framework <jekyll|rails>   Framework to run (default: jekyll)"
    echo "  --host <HOST>                Host address (default: 127.0.0.1)"
    echo "  --port <PORT>                Port number (default: 4000)"
    echo "  --draft                      Include draft content (only for jekyll)"
    echo "  -h, --help                   Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                           Run default jekyll server on 127.0.0.1:4000"
    echo "  $0 --framework rails         Start a Rails server"
    echo "  $0 --host 0.0.0.0 --port 8080 --draft"
    echo ""
}

# If no args were given, mark for help display later
if [ "$#" -eq 0 ]; then
    show_help_after_run=true
fi

# Parse optional parameters
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --draft)
            DRAFT=true
            ;;
        --framework)
            FRAMEWORK="$2"
            shift
            ;;
        --host)
            HOST="$2"
            shift
            ;;
        --port)
            PORT="$2"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "[ERROR] Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
    shift
done

# Function: Kill any existing process using the port
kill_existing_process() {
    local port=$1
    local pids
    pids=$(lsof -ti :$port 2>/dev/null)

    if [ $? -ne 0 ]; then
        echo "[ERROR] lsof failed to check port $port. Is 'lsof' installed?"
        show_help
        exit 1
    fi

    if [ -n "$pids" ]; then
        echo "[INFO] Port $port is in use. Terminating process(es): $pids"

        for pid in $pids; do
            kill -9 "$pid"
            if [ $? -ne 0 ]; then
                echo "[ERROR] Failed to kill process $pid on port $port."
                show_help
                exit 1
            else
                echo "[INFO] Process $pid terminated."
            fi
        done
    else
        echo "[INFO] No process found using port $port."
    fi
}

# Kill any existing process using the specified port
kill_existing_process "$PORT"

# Set draft flag
DRAFT_FLAG=""
if [ "$DRAFT" = true ]; then
    DRAFT_FLAG="--draft"
fi

# Start the appropriate server
echo "[INFO] Starting $FRAMEWORK server on $HOST:$PORT (draft mode: $DRAFT)"

case "$FRAMEWORK" in
    rails)
        bundle exec rails server -b "$HOST" -p "$PORT" $DRAFT_FLAG
        ;;
    jekyll)
        bundle exec jekyll serve --host "$HOST" --port "$PORT" $DRAFT_FLAG
        ;;
    *)
        echo "[ERROR] Unsupported framework: $FRAMEWORK"
        show_help
        exit 1
        ;;
esac

# If no args were given, show help after running
if [ "$show_help_after_run" = true ]; then
    echo ""
    echo "[INFO] Script ran with default settings. Here's how to customize it:"
    show_help
fi
