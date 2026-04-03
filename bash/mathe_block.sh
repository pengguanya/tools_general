#!/usr/bin/env bash
# mathe_block.sh - Present math exercises and collect answers interactively
# Usage: mathe_block.sh <block_num> <exercises_json>
#
# exercises_json is a JSON array of objects: [{"q":"14 x 7","a":98}, ...]
# Output: JSON array of user answers: [{"q":"14 x 7","a":98,"user":"98"}, ...]
#
# If user enters empty answer, re-asks once. Second empty = "" (no answer).

set -euo pipefail

BLOCK_NUM="${1:?Usage: mathe_block.sh <block_num> <exercises_json>}"
EXERCISES_JSON="${2:?Usage: mathe_block.sh <block_num> <exercises_json>}"

# Parse exercises into arrays
TOTAL=$(echo "$EXERCISES_JSON" | jq 'length')
RESULTS="[]"

for ((i=0; i<TOTAL; i++)); do
    Q=$(echo "$EXERCISES_JSON" | jq -r ".[$i].q")
    A=$(echo "$EXERCISES_JSON" | jq -r ".[$i].a")
    NUM=$((i + 1))

    # Present question
    echo ""
    echo "Block $BLOCK_NUM, Aufgabe $NUM/$TOTAL: $Q = "
    read -r -p "> " USER_ANS

    # If empty, re-ask once
    if [[ -z "$USER_ANS" ]]; then
        echo "Bitte gib deine Antwort ein:"
        read -r -p "> " USER_ANS
        # Second empty = no answer
        if [[ -z "$USER_ANS" ]]; then
            USER_ANS=""
        fi
    fi

    # Append to results
    RESULTS=$(echo "$RESULTS" | jq \
        --arg q "$Q" \
        --arg a "$A" \
        --arg u "$USER_ANS" \
        '. + [{"q": $q, "a": ($a | tonumber), "user": $u}]')
done

echo ""
echo "--- Block $BLOCK_NUM abgeschlossen! ---"
echo ""

# Output results as JSON on a special marker line so Claude can parse it
echo "RESULTS_JSON:$RESULTS"
