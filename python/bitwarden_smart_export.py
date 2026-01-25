#!/usr/bin/env python3
"""
Bitwarden Smart Export from Pass

Exports passwords from the Unix password-store (pass) to Bitwarden-compatible
CSV format. Configurable parsing strategies adapt to different directory structures.

Usage:
    bitwarden_smart_export.py [OPTIONS]

Configuration:
    Adjust PARSING_STRATEGY and related options in the script to match your pass structure,
    or use command-line options to override.

Output:
    Creates bitwarden_smart_import.csv in the current directory.
    WARNING: Output contains plaintext passwords - delete after importing!
"""
import os
import csv
import subprocess
import sys
import re
import argparse

# ============================================================================
# CONFIGURATION - Adjust these settings to match your pass directory structure
# ============================================================================
#
# QUICK START GUIDE:
#
# 1. Choose a parsing strategy that matches your current pass structure:
#    - "heuristic": Most flexible, works with mixed/irregular structures
#    - "depth-based": For consistent hierarchies (e.g., always Category/Service/user)
#    - "flat": Simple import, no hierarchy (all in one folder)
#
# 2. If your structure changes in the future:
#    - Switch PARSING_STRATEGY to match new layout
#    - Adjust strategy-specific config below (only active strategy is used)
#    - Run script again to generate updated CSV
#
# 3. Testing:
#    - Run the script and check the console output
#    - Verify a few entries in the generated CSV
#    - Import a test entry to Bitwarden before importing everything
#
# ============================================================================

# Path to your password store (usually ~/.password-store)
PASSWORD_STORE_DIR = os.path.expanduser("~/.password-store")

# Output CSV file
OUTPUT_FILE = "bitwarden_smart_import.csv"

# Parsing Strategy: Choose how to interpret your directory structure
# Options:
#   "depth-based"  : Use fixed depth levels (folder/name/username pattern)
#   "heuristic"    : Smart detection based on naming patterns (URLs, etc.)
#   "flat"         : All entries in one folder, no hierarchy
#
# Examples:
#   Structure: Category/Service/username.gpg
#   - heuristic: folder="Category", name="Service", username="username"
#   - depth-based with folder_levels=[0], name_level=1: Same as above
#   - flat: folder="Imported", name="Category/Service/username"
#
#   Structure: github.com/user.gpg (flat with URLs)
#   - heuristic: folder="", name="github.com", url="github.com"
#   - flat: folder="Imported", name="github.com/user"
PARSING_STRATEGY = "heuristic"

# Depth-based strategy settings (only used if PARSING_STRATEGY = "depth-based")
# Best for: Consistent hierarchical structures with predictable depth
# Example: Category/SubCategory/Service/user.gpg
DEPTH_CONFIG = {
    "folder_levels": [0],        # Path levels to combine as folder
                                  # [0] = first level only, [0,1] = first two levels
    "name_level": 1,              # Which level is the item name (0-indexed)
    "username_from": "filename",  # "filename" = use file.gpg name
                                  # "parent_dir" = use immediate parent directory
}

# Heuristic strategy settings (only used if PARSING_STRATEGY = "heuristic")
# Best for: Mixed structures with URLs and variable depth
# Automatically detects URLs and adapts to different path depths
HEURISTIC_CONFIG = {
    "url_detection_regex": r".*\.(com|org|net|io|dev|co|edu|gov)$",
                                  # Regex pattern to identify URL-like names
                                  # Add more TLDs as needed: |app|cloud|local
    "min_folder_depth": 0,        # Minimum depth to treat as folder (0 = always use)
                                  # Set to 1 to treat single-level paths as items
    "username_from": "filename",  # "filename", "parent_dir", or "none"
}

# Flat strategy settings (only used if PARSING_STRATEGY = "flat")
# Best for: Simple migration or restructuring, puts everything in one folder
FLAT_CONFIG = {
    "default_folder": "Imported",  # All entries go into this folder
    "name_from": "full_path",      # "full_path" = preserve path as name
                                    # "filename" = just use filename as name
}

def get_gpg_content(filepath):
    """
    Decrypts a GPG file using the pass command.

    Args:
        filepath: Full path to the .gpg file to decrypt.

    Returns:
        str: Decrypted content, or None if decryption fails.
    """
    try:
        # We use the relative path for 'pass show' to mimic standard usage
        rel_path = os.path.relpath(filepath, PASSWORD_STORE_DIR)
        name_for_pass = os.path.splitext(rel_path)[0]

        result = subprocess.check_output(
            ["pass", "show", name_for_pass], 
            stderr=subprocess.DEVNULL
        ).decode('utf-8')
        return result
    except Exception as e:
        print(f"Error reading {filepath}: {e}", file=sys.stderr)
        return None

def _extract_username_from_filename(filename):
    """
    Extracts username from a .gpg filename.

    Args:
        filename: The filename (e.g., "user.gpg").

    Returns:
        str: Username without .gpg extension.
    """
    if filename.endswith(".gpg"):
        return filename[:-4]
    return filename


def _parse_depth_based(parts, dir_parts):
    """
    Parses path using fixed depth-based configuration.

    Args:
        parts: Full path components including filename.
        dir_parts: Path components excluding filename.

    Returns:
        tuple: (folder, name, username, url) as strings.
    """
    config = DEPTH_CONFIG

    # Extract username
    if config["username_from"] == "filename":
        username = _extract_username_from_filename(parts[-1])
    elif config["username_from"] == "parent_dir" and dir_parts:
        username = dir_parts[-1]
    else:
        username = ""

    # Extract folder
    folder_levels = config["folder_levels"]
    folder_parts = [dir_parts[i] for i in folder_levels if i < len(dir_parts)]
    folder = "/".join(folder_parts) if folder_parts else ""

    # Extract name
    name_level = config["name_level"]
    if name_level < len(dir_parts):
        name = dir_parts[name_level]
    else:
        name = username

    # Detect URL
    url = name if re.match(HEURISTIC_CONFIG["url_detection_regex"], name) else ""

    return folder, name, username, url


def _parse_heuristic(parts, dir_parts):
    """
    Parses path using heuristic pattern detection.

    Uses intelligent detection of URLs and flexible folder/name assignment
    based on path depth and naming patterns.

    Args:
        parts: Full path components including filename.
        dir_parts: Path components excluding filename.

    Returns:
        tuple: (folder, name, username, url) as strings.
    """
    config = HEURISTIC_CONFIG

    # Extract username
    if config["username_from"] == "filename":
        username = _extract_username_from_filename(parts[-1])
    elif config["username_from"] == "parent_dir" and dir_parts:
        username = dir_parts[-1]
    else:
        username = ""

    # Handle root-level files
    if not dir_parts:
        return "", username, username, ""

    # The immediate parent is usually the item name
    name = dir_parts[-1]

    # Everything before the immediate parent becomes the folder hierarchy
    if len(dir_parts) > 1:
        folder = "/".join(dir_parts[:-1])
    else:
        folder = dir_parts[0] if len(dir_parts) == 1 and config["min_folder_depth"] == 0 else ""

    # Detect URL using regex pattern
    url = name if re.match(config["url_detection_regex"], name) else ""

    return folder, name, username, url


def _parse_flat(parts, dir_parts):
    """
    Parses path using flat structure (all in one folder).

    Args:
        parts: Full path components including filename.
        dir_parts: Path components excluding filename.

    Returns:
        tuple: (folder, name, username, url) as strings.
    """
    config = FLAT_CONFIG

    username = _extract_username_from_filename(parts[-1])
    folder = config["default_folder"]

    if config["name_from"] == "full_path":
        name = "/".join(parts[:-1] + [username]) if dir_parts else username
    else:
        name = username

    url = ""

    return folder, name, username, url


def parse_path(rel_path):
    """
    Parses pass directory structure using the configured strategy.

    Dispatches to the appropriate parsing function based on PARSING_STRATEGY.
    Supports multiple strategies for different directory structures.

    Args:
        rel_path: Relative path from PASSWORD_STORE_DIR (e.g., "Work/Site/user.gpg").

    Returns:
        tuple: (folder, name, username, url) as strings.
    """
    parts = rel_path.split(os.sep)
    dir_parts = parts[:-1]  # Everything except filename

    # Dispatch to appropriate parsing strategy
    if PARSING_STRATEGY == "depth-based":
        return _parse_depth_based(parts, dir_parts)
    elif PARSING_STRATEGY == "heuristic":
        return _parse_heuristic(parts, dir_parts)
    elif PARSING_STRATEGY == "flat":
        return _parse_flat(parts, dir_parts)
    else:
        raise ValueError(f"Unknown parsing strategy: {PARSING_STRATEGY}")

def main():
    """
    Main entry point for the password export process.

    Walks through PASSWORD_STORE_DIR, decrypts all .gpg files, parses their
    structure, and writes a Bitwarden-compatible CSV file.
    """
    global PARSING_STRATEGY, PASSWORD_STORE_DIR, OUTPUT_FILE

    parser = argparse.ArgumentParser(
        description="Export passwords from pass (Unix password-store) to Bitwarden CSV format.",
        epilog="WARNING: Output file contains plaintext passwords. Delete after importing!",
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    parser.add_argument(
        "-o", "--output",
        default=OUTPUT_FILE,
        help=f"Output CSV file (default: {OUTPUT_FILE})"
    )

    parser.add_argument(
        "-s", "--strategy",
        choices=["heuristic", "depth-based", "flat"],
        default=PARSING_STRATEGY,
        help=f"Parsing strategy to use (default: {PARSING_STRATEGY})"
    )

    parser.add_argument(
        "-d", "--dir",
        default=PASSWORD_STORE_DIR,
        help=f"Password store directory (default: {PASSWORD_STORE_DIR})"
    )

    parser.add_argument(
        "--list-strategies",
        action="store_true",
        help="List available parsing strategies and exit"
    )

    args = parser.parse_args()

    if args.list_strategies:
        print("Available parsing strategies:")
        print("  heuristic    : Smart detection, adapts to mixed structures (recommended)")
        print("  depth-based  : Fixed depth levels, for consistent hierarchies")
        print("  flat         : All entries in one folder, simple import")
        print("\nEdit the script to configure strategy-specific settings.")
        sys.exit(0)

    # Override global settings with command-line arguments
    PARSING_STRATEGY = args.strategy
    PASSWORD_STORE_DIR = os.path.expanduser(args.dir)
    OUTPUT_FILE = args.output

    print(f"Starting export using '{PARSING_STRATEGY}' strategy...")
    print(f"Reading from: {PASSWORD_STORE_DIR}")
    print(f"Output file: {OUTPUT_FILE}\n")

    with open(OUTPUT_FILE, mode='w', newline='', encoding='utf-8') as csv_file:
        writer = csv.writer(csv_file)
        # Bitwarden standard headers
        writer.writerow(['folder', 'name', 'login_username', 'login_password', 'login_uri', 'notes'])

        for root, dirs, files in os.walk(PASSWORD_STORE_DIR):
            for file in files:
                if file.endswith(".gpg"):
                    full_path = os.path.join(root, file)
                    rel_path = os.path.relpath(full_path, PASSWORD_STORE_DIR)

                    # Decrypt
                    content = get_gpg_content(full_path)
                    if not content:
                        continue

                    lines = content.splitlines()
                    password = lines[0] if lines else ""
                    # Put extra lines in notes
                    notes = "\n".join(lines[1:]) if len(lines) > 1 else ""

                    # Parse Structure
                    folder, name, username, url = parse_path(rel_path)

                    writer.writerow([folder, name, username, password, url, notes])
                    print(f"Processed: {folder} -> {name} ({username})")

    print(f"\nDone! Saved to {OUTPUT_FILE}")
    print("WARNING: This file contains plain text passwords. Delete it after importing!")

if __name__ == "__main__":
    main()
