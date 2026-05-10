#!/bin/bash
#
# clean_transcript.sh — Clean a single timestamped transcript file
# Strips timestamps (M:SS, MM:SS, H:MM:SS), trims whitespace,
# and joins all lines into a single flowing paragraph.
#
# Usage: clean-transcript <input.txt> [output.txt]

show_help() {
    cat <<EOF
Usage: $(basename "$0") <input.txt> [output.txt]

Strips timestamps and joins continuation lines into a single paragraph,
producing token-efficient output for LLM consumption.

Handles:
  - Standalone timestamp lines (0:01, 1:23:45)
  - Timestamps with trailing whitespace
  - Inline timestamps at line start (0:01 Welcome...)
  - Missing or partial timestamps
  - Blank lines and extra whitespace

Arguments:
  input.txt    Source transcript file
  output.txt   Output file (default: <input>_clean.txt)
EOF
    exit 0
}

[[ "$1" == "-h" || "$1" == "--help" ]] && show_help

input="${1:?Usage: $(basename "$0") input.txt [output.txt]}"
output="${2:-${input%.txt}_clean.txt}"

if [[ ! -f "$input" ]]; then
    echo "Error: File not found: $input" >&2
    exit 1
fi

sed -E '
  /^[[:space:]]*[0-9]{1,2}(:[0-9]{2}){1,2}[[:space:]]*$/d
  s/^[[:space:]]*[0-9]{1,2}(:[0-9]{2}){1,2}[[:space:]]+//
' "$input" |
  awk '
    NF == 0 { next }
    {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      if (NF > 0) para = (para ? para " " : "") $0
    }
    END { if (para) print para }
  ' > "$output"

echo "✓ $(basename "$input") → $(basename "$output")"
