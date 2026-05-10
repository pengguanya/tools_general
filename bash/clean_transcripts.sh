#!/bin/bash
#
# clean_transcripts.sh — Recursively find and clean timestamped transcripts
# Wrapper around clean-transcript for batch processing across directory trees.
#
# Usage: clean-transcripts [OPTIONS] <dir> [dir2 ...]

set -e

# --- Constants ---
DEFAULT_PATTERN="transcript.txt"
DEFAULT_SUFFIX="_clean"
DEFAULT_PREVIEW_CHARS=200
CLEAN_CMD="clean-transcript"

# --- Help ---
show_help() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] <directory> [directory2 ...]

Recursively find and clean timestamped transcript files.

Options:
  -p, --pattern GLOB    File pattern to match (default: "$DEFAULT_PATTERN")
  -s, --suffix STRING   Suffix for cleaned files (default: "$DEFAULT_SUFFIX")
  -n, --preview-chars N Characters to preview per file (default: $DEFAULT_PREVIEW_CHARS)
  -f, --force           Overwrite existing cleaned files
  --no-preview          Skip preview and replacement prompt
  -y, --auto-approve    Show preview but replace automatically (no interactive prompt)
  -d, --dry-run         Show what would be cleaned, don't do it
  -h, --help            Show this help

Examples:
  $(basename "$0") ./courses
  $(basename "$0") -p "*.txt" ./lectures ./seminars
  $(basename "$0") -p "lesson*.txt" -s "_processed" ./courses
  $(basename "$0") --dry-run -p "*.txt" ./courses
  $(basename "$0") --auto-approve ./courses
  $(basename "$0") --no-preview --force ./courses

Output files are written alongside the originals with the suffix appended
before the extension: transcript.txt → transcript_clean.txt

After cleaning, a preview of each file is shown and you are prompted to
replace the originals. Use --no-preview to skip this.
EOF
    exit 0
}

# --- Core functions ---

build_output_path() {
    local input="$1"
    local ext="${input##*.}"
    local base="${input%.*}"
    echo "${base}${suffix}.${ext}"
}

find_transcripts() {
    local dir="$1"
    find "$dir" -type f -name "$pattern" | grep -v "${suffix}\." | sort
}

show_preview() {
    local input="$1"
    local output="$2"
    local dir
    dir=$(dirname "$input")

    echo ""
    echo "─────────────────────────────────────────────────────"
    echo "  File: $(basename "$input")"
    echo "  Path: $dir"
    echo "─────────────────────────────────────────────────────"
    echo -n "  "
    head -c "$preview_chars" "$output"
    local file_chars
    file_chars=$(wc -c < "$output")
    if [[ "$file_chars" -gt "$preview_chars" ]]; then
        echo "..."
        echo "  [$(( file_chars - preview_chars )) more characters]"
    else
        echo ""
    fi
}

process_file() {
    local input="$1"
    local output
    output=$(build_output_path "$input")

    if [[ -f "$output" && "$force" != true ]]; then
        echo "  skip: $(basename "$output") already exists (use --force to overwrite)"
        skipped=$((skipped + 1))
        return
    fi

    if [[ "$dry_run" == true ]]; then
        echo "  would clean: $input → $output"
        would_process=$((would_process + 1))
        return
    fi

    if "$CLEAN_CMD" "$input" "$output" 2>/dev/null; then
        processed_files+=("$input")
        processed=$((processed + 1))
    else
        echo "  ✗ failed: $input" >&2
        errors=$((errors + 1))
    fi
}

# --- Argument parsing ---
pattern="$DEFAULT_PATTERN"
suffix="$DEFAULT_SUFFIX"
preview_chars="$DEFAULT_PREVIEW_CHARS"
force=false
dry_run=false
preview=true
auto_approve=false
dirs=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--pattern)       pattern="$2";       shift 2 ;;
        -s|--suffix)        suffix="$2";        shift 2 ;;
        -n|--preview-chars) preview_chars="$2";  shift 2 ;;
        -f|--force)         force=true;         shift ;;
        --no-preview)       preview=false;      shift ;;
        -y|--auto-approve)  auto_approve=true;  shift ;;
        -d|--dry-run)       dry_run=true;       shift ;;
        -h|--help)          show_help ;;
        -*)
            echo "Unknown option: $1" >&2
            echo "Run '$(basename "$0") --help' for usage." >&2
            exit 1
            ;;
        *) dirs+=("$1"); shift ;;
    esac
done

if [[ ${#dirs[@]} -eq 0 ]]; then
    echo "Error: No directories specified." >&2
    echo "Run '$(basename "$0") --help' for usage." >&2
    exit 1
fi

# --- Validate ---
if ! command -v "$CLEAN_CMD" &>/dev/null; then
    echo "Error: '$CLEAN_CMD' not found in PATH." >&2
    echo "Run 'setup_symlinks' to register it." >&2
    exit 1
fi

for dir in "${dirs[@]}"; do
    if [[ ! -d "$dir" ]]; then
        echo "Error: Not a directory: $dir" >&2
        exit 1
    fi
done

# --- Main ---
processed=0
skipped=0
errors=0
would_process=0
found=0
processed_files=()

[[ "$dry_run" == true ]] && echo "Dry run — no files will be modified."
echo "Pattern: $pattern"
echo ""

for dir in "${dirs[@]}"; do
    echo "Scanning: $dir"
    while IFS= read -r file; do
        found=$((found + 1))
        process_file "$file"
    done < <(find_transcripts "$dir")
done

# --- Summary ---
echo ""
if [[ "$dry_run" == true ]]; then
    echo "Found $found file(s), $would_process would be cleaned."
    exit 0
fi

echo "Done. Processed: $processed | Skipped: $skipped | Errors: $errors"

# --- Preview & Replace ---
if [[ "$preview" == true && ${#processed_files[@]} -gt 0 ]]; then
    echo ""
    echo "===== Preview of cleaned transcripts ====="

    for input in "${processed_files[@]}"; do
        output=$(build_output_path "$input")
        show_preview "$input" "$output"
    done

    echo ""
    echo "─────────────────────────────────────────────────────"
    echo ""

    if [[ "$auto_approve" == true ]]; then
        answer="y"
        echo "Auto-approving replacement of ${#processed_files[@]} file(s)."
    else
        read -r -p "Replace ${#processed_files[@]} original(s) with cleaned versions? [y/N] " answer
    fi

    if [[ "$answer" =~ ^[Yy]$ ]]; then
        replaced=0
        for input in "${processed_files[@]}"; do
            output=$(build_output_path "$input")
            mv "$output" "$input"
            replaced=$((replaced + 1))
            echo "  ✓ replaced: $input"
        done
        echo ""
        echo "Replaced $replaced file(s). Cleaned intermediates removed."
    else
        echo "No files replaced. Cleaned files kept alongside originals."
    fi
fi
