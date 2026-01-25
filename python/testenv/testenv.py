#!/usr/bin/env python3
"""
Test Environment Validator

Simple test script to verify a Python virtual environment is correctly set up
and that pyfiglet is installed. Displays "It Works!" in ASCII art if successful.

Usage:
    testenv.py [OPTIONS]
"""
import sys
import argparse

def main():
    """
    Main entry point for the test environment validator.

    Tests if pyfiglet is installed and displays success message.
    """
    parser = argparse.ArgumentParser(
        description="Test Python environment by displaying ASCII art using pyfiglet."
    )

    parser.add_argument(
        "-m", "--message",
        default="It Works!",
        help="Custom message to display (default: 'It Works!')"
    )

    parser.add_argument(
        "-f", "--font",
        default="standard",
        help="Pyfiglet font to use (default: standard)"
    )

    args = parser.parse_args()

    try:
        import pyfiglet
        print(pyfiglet.figlet_format(args.message, font=args.font))
    except ImportError:
        print("ERROR: pyfiglet is not installed.", file=sys.stderr)
        print("Install it with: pip install pyfiglet", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
