#!/bin/bash
#
# Script Name: makecmd.sh
# Description: Thin wrapper for setup_symlinks add (backward compatibility)
# Usage: makecmd <script> [name]
#

exec "$(dirname "$0")/setup_symlinks.sh" add "$@"
