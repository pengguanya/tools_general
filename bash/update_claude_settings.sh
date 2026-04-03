#!/bin/bash

# Source the environment variables
# Adjust this path if your .common_env.sh is located elsewhere
if [ -f "$HOME/.common_env.sh" ]; then
    source "$HOME/.common_env.sh"
fi

# Set defaults for variables used in settings.json if they are not already set
# These defaults match what was originally in your settings.json
: "${ANTHROPIC_MODEL:=eu.anthropic.claude-sonnet-4-5-20250929-v1:0}"
: "${ANTHROPIC_SMALL_FAST_MODEL:=eu.anthropic.claude-3-haiku-20240307-v1:0}"
: "${ANTHROPIC_DEFAULT_MODEL:=us.anthropic.claude-opus-4-5-20251101-v1:0}"

# Export them so envsubst can see them
export ANTHROPIC_BEDROCK_BASE_URL
export PORTKEY_CLAUDE_API_KEY
export ANTHROPIC_MODEL
export ANTHROPIC_SMALL_FAST_MODEL
export ANTHROPIC_DEFAULT_MODEL

# Validate required variables
if [ -z "$ANTHROPIC_BEDROCK_BASE_URL" ]; then
    echo "Error: ANTHROPIC_BEDROCK_BASE_URL is not set."
    exit 1
fi
if [ -z "$PORTKEY_CLAUDE_API_KEY" ]; then
    echo "Error: PORTKEY_CLAUDE_API_KEY is not set."
    exit 1
fi

# File locations
TEMPLATE_FILE="$HOME/.claude/settings.json.template"
SETTINGS_FILE="$HOME/.claude/settings.json"

if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "Error: Template file $TEMPLATE_FILE not found."
    exit 1
fi

# Backup existing settings if present
if [ -f "$SETTINGS_FILE" ]; then
    cp "$SETTINGS_FILE" "$SETTINGS_FILE.bak"
fi

# Generate settings.json from template (restrict to specific variables)
ENVSUBST_VARS='$ANTHROPIC_BEDROCK_BASE_URL $PORTKEY_CLAUDE_API_KEY $ANTHROPIC_MODEL $ANTHROPIC_SMALL_FAST_MODEL $ANTHROPIC_DEFAULT_MODEL'
if envsubst "$ENVSUBST_VARS" < "$TEMPLATE_FILE" > "$SETTINGS_FILE"; then
    echo "Successfully generated $SETTINGS_FILE"
    echo "Variables used:"
    echo "  ANTHROPIC_MODEL: $ANTHROPIC_MODEL"
    echo "  ANTHROPIC_SMALL_FAST_MODEL: $ANTHROPIC_SMALL_FAST_MODEL"
    echo "  Bedrock Base URL: ${ANTHROPIC_BEDROCK_BASE_URL:-(not set)}"
else
    echo "Error: Failed to generate settings.json"
    exit 1
fi
