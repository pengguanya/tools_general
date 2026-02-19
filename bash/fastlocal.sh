#!/bin/bash
#
# Script Name: fastlocal.sh
# Description: Launch FastAPI dev server, auto-killing conflicting processes
# Usage: ./fastlocal.sh [FILE] [PORT]
# Requirements: fastapi CLI, lsof
# Example: ./fastlocal.sh app.py 8080
#

set -e

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: $0 [FILE] [PORT]"
    echo "  FILE  Python file with FastAPI app (default: main.py)"
    echo "  PORT  Port to use (default: 8000)"
    exit 0
fi

FILE=${1:-"main.py"}
PORT=${2:-8000}

echo "🚀 Preparing to launch FastAPI on port $PORT..."

PID=$(lsof -ti :"$PORT" 2>/dev/null || true)

if [[ -n "$PID" ]]; then
    echo "⚠️  Port $PORT is occupied by PID(s): $PID. Terminating..."
    kill -9 $PID 2>/dev/null || true
    sleep 0.5
    echo "✅ Port $PORT cleared."
else
    echo "✨ Port $PORT is already free."
fi

fastapi dev "$FILE" --port "$PORT"
