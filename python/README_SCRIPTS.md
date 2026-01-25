# Python Scripts Usage Guide

## Overview

All scripts are executable and provide `--help` options for detailed usage information.

## Scripts

### 1. xls2xml.py
**Purpose:** Convert Excel files (.xlsx, .xls) or XML Spreadsheet 2003 format to CSV

**Usage:**
```bash
./xls2xml.py filename.xls > output.csv
./xls2xml.py --help
```

**Features:**
- Handles ragged/irregular XML spreadsheets
- Outputs to stdout for easy piping
- Supports standard Excel formats and XML Spreadsheet 2003

---

### 2. bitwarden_smart_export.py
**Purpose:** Export passwords from pass (Unix password-store) to Bitwarden CSV format

**Usage:**
```bash
./bitwarden_smart_export.py                    # Use default settings
./bitwarden_smart_export.py -o custom.csv      # Custom output file
./bitwarden_smart_export.py -s flat            # Use flat strategy
./bitwarden_smart_export.py --list-strategies  # Show available strategies
./bitwarden_smart_export.py --help
```

**Options:**
- `-o, --output FILE`: Output CSV file (default: bitwarden_smart_import.csv)
- `-s, --strategy`: Choose parsing strategy (heuristic, depth-based, flat)
- `-d, --dir`: Password store directory (default: ~/.password-store)
- `--list-strategies`: List available parsing strategies

**Parsing Strategies:**
- **heuristic** (default): Smart detection, adapts to mixed structures
- **depth-based**: Fixed depth levels for consistent hierarchies
- **flat**: All entries in one folder for simple import

**Configuration:**
Edit the script to adjust strategy-specific settings:
- URL detection patterns
- Folder depth handling
- Username extraction methods

---

### 3. testenv/testenv.py
**Purpose:** Test Python environment and pyfiglet installation

**Usage:**
```bash
./testenv/testenv.py                      # Default message
./testenv/testenv.py -m "Hello World"     # Custom message
./testenv/testenv.py -f banner            # Different font
./testenv/testenv.py --help
```

**Options:**
- `-m, --message`: Custom message to display (default: "It Works!")
- `-f, --font`: Pyfiglet font to use (default: standard)

---

## Making Scripts Available System-Wide

To use these scripts from anywhere, add symlinks to your PATH:

```bash
# Create a local bin directory if it doesn't exist
mkdir -p ~/bin

# Create symlinks (adjust paths as needed)
ln -s $(pwd)/xls2xml.py ~/bin/xls2xml
ln -s $(pwd)/bitwarden_smart_export.py ~/bin/bitwarden-export
ln -s $(pwd)/testenv/testenv.py ~/bin/testenv

# Make sure ~/bin is in your PATH (add to ~/.bashrc or ~/.zshrc)
export PATH="$HOME/bin:$PATH"
```

---

## Security Notes

- **bitwarden_smart_export.py** creates files with plaintext passwords
- Delete output CSV files immediately after importing to Bitwarden
- Never commit CSV files to version control
- Review the generated CSV before importing

---

## Examples

### Convert Excel to CSV and process with other tools
```bash
./xls2xml.py data.xls | grep "keyword" | sort > filtered.csv
```

### Export passwords with custom strategy
```bash
./bitwarden_smart_export.py -s depth-based -o work_passwords.csv
```

### Test environment with custom ASCII art
```bash
./testenv/testenv.py -m "Production Ready" -f banner
```
