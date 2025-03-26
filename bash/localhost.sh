#!/bin/bash

# Default values
HOST="127.0.0.1"
PORT=4000
DRAFT=false
FRAMEWORK="jekyll"  # Default framework is now jekyll

# Parse optional parameters
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --drafts)
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
        --help)
            echo "Usage: $0 [--framework jekyll|rails|other] [--host HOST] [--port PORT] [--draft]"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help to see available options."
            exit 1
            ;;
    esac
    shift
done

# Function to find and kill process using the port
kill_existing_process() {
    local port=$1
    local pid=$(lsof -ti :$port)
    if [ ! -z "$pid" ]; then
        echo "Port $port is in use. Terminating process $pid..."
        kill -9 $pid
        echo "Process $pid terminated."
    else
        echo "No process found using port $port."
    fi
}

# Kill any existing process using the specified port
kill_existing_process "$PORT"

# Set draft flag
DRAFT_FLAG=""
if [ "$DRAFT" = true ]; then
    DRAFT_FLAG="--drafts"
fi

# Start the appropriate server
echo "Starting $FRAMEWORK server on $HOST:$PORT with draft mode: $DRAFT"

case "$FRAMEWORK" in
    rails)
        bundle exec rails server -b "$HOST" -p "$PORT" $DRAFT_FLAG
        ;;
    jekyll)
        bundle exec jekyll serve --host "$HOST" --port "$PORT" $DRAFT_FLAG
        ;;
    *)
        echo "Unsupported framework: $FRAMEWORK"
        echo "Only 'jekyll' and 'rails' are supported currently."
        exit 1
        ;;
esac
