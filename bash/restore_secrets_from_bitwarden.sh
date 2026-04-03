#!/bin/bash
# Restore secrets from Bitwarden to ~/.common_env.sh
# This script fetches API tokens from Bitwarden cloud vault and creates ~/.common_env.sh

set -e

echo "=== Restoring Secrets from Bitwarden ==="

# Check if bw is installed
if ! command -v bw &> /dev/null; then
    echo "Error: Bitwarden CLI not installed."
    echo "Install with: sudo snap install bw"
    echo "Or download from: https://bitwarden.com/download/"
    exit 1
fi

# Check if jq is installed (needed for JSON parsing)
if ! command -v jq &> /dev/null; then
    echo "Error: jq not installed."
    echo "Install with: sudo apt install jq"
    exit 1
fi

# Check if logged in
if ! bw login --check &> /dev/null; then
    echo "Not logged in to Bitwarden."
    echo ""

    # Try to use API key from ~/bitwarden_tokens.txt
    if [ -f "$HOME/bitwarden_tokens.txt" ]; then
        echo "Found API credentials in ~/bitwarden_tokens.txt"
        echo "Logging in with API key..."

        # Parse the token file
        BW_CLIENTID=$(grep -A1 "client_id:" "$HOME/bitwarden_tokens.txt" | tail -1 | tr -d ' ')
        BW_CLIENTSECRET=$(grep -A1 "client_secret:" "$HOME/bitwarden_tokens.txt" | tail -1 | tr -d ' ')

        if [ -n "$BW_CLIENTID" ] && [ -n "$BW_CLIENTSECRET" ]; then
            # Set environment variables for API key login
            export BW_CLIENTID
            export BW_CLIENTSECRET

            # Login with API key
            bw login --apikey
        else
            echo "Error: Could not parse API credentials from ~/bitwarden_tokens.txt"
            exit 1
        fi
    else
        echo "Please login to Bitwarden manually:"
        echo "  bw login --apikey"
        echo "Or place API credentials in ~/bitwarden_tokens.txt"
        exit 1
    fi
fi

# Unlock vault and get session key
echo ""
echo "Unlocking Bitwarden vault..."

# Get master password from pass
BW_MASTER_PASSWORD=$(pass show Personal/Bitwarden/vault.bitwarden.com/guanya.peng24@gmail.com 2>/dev/null | head -1 || true)

if [ -z "$BW_MASTER_PASSWORD" ]; then
    echo "Error: Could not retrieve master password from pass"
    echo "Please unlock manually: bw unlock"
    exit 1
fi

# Unlock with master password
BW_SESSION=$(printf "%s\n" "$BW_MASTER_PASSWORD" | bw unlock --raw 2>&1 | tail -1)

if [ -z "$BW_SESSION" ] || [ ${#BW_SESSION} -lt 20 ]; then
    echo "Error: Failed to unlock vault"
    printf "%s\n" "$BW_MASTER_PASSWORD" | bw unlock --raw 2>&1
    exit 1
fi

export BW_SESSION
echo "✓ Vault unlocked successfully"

# Get the secure note item
echo "Fetching secrets from Bitwarden..."
echo "Looking for: 'Ubuntu Dev Environment - API Tokens' in 'Ubuntu Migration' folder..."
ITEM_ID=$(bw list items --search "Ubuntu Dev Environment - API Tokens" 2>/dev/null | jq -r '.[0].id')

if [ -z "$ITEM_ID" ] || [ "$ITEM_ID" = "null" ]; then
    echo "Error: Could not find 'Ubuntu Dev Environment - API Tokens' in Bitwarden"
    echo ""
    echo "Please create a secure note with this name and add your API tokens as custom fields."
    echo "You can use the upload_secrets_to_bitwarden script to do this automatically."
    echo "See migration documentation for details."
    bw lock
    exit 1
fi

echo "✓ Found item (ID: $ITEM_ID)"

# Fetch the item
ITEM=$(bw get item "$ITEM_ID" 2>/dev/null)

if [ -z "$ITEM" ]; then
    echo "Error: Could not fetch item from Bitwarden"
    bw lock
    exit 1
fi

# Helper function to extract field value
get_field() {
    local field_name="$1"
    echo "$ITEM" | jq -r ".fields[] | select(.name==\"$field_name\") | .value" 2>/dev/null || echo ""
}

# Extract all secrets
echo "Extracting secrets..."
GITLAB_READ_REGISTRY=$(get_field "GITLAB_READ_REGISTRY")
VAULT_TOKEN=$(get_field "VAULT_TOKEN")
VAULT_ADDR=$(get_field "VAULT_ADDR")
VAULT_NAMESPACE=$(get_field "VAULT_NAMESPACE")
RSCONNECT_SERVER=$(get_field "RSCONNECT_SERVER")
RSCONNECT_TOKEN=$(get_field "RSCONNECT_TOKEN")
GITHUB_PAT=$(get_field "GITHUB_PAT")
GITHUB_TOKEN=$(get_field "GITHUB_TOKEN")
GITLAB_TOKEN=$(get_field "GITLAB_TOKEN")
OCR_API_KEY=$(get_field "OCR_API_KEY")
DIAGNOSTIC_TOKEN=$(get_field "DIAGNOSTIC_TOKEN")
PACKAGEMANAGER_TOKEN=$(get_field "PACKAGEMANAGER_TOKEN")
JIRA_API_TOKEN=$(get_field "JIRA_API_TOKEN")
OPENAI_ACCESS_KEY=$(get_field "OPENAI_ACCESS_KEY")
ANTHROPIC_BEDROCK_BASE_URL=$(get_field "ANTHROPIC_BEDROCK_BASE_URL")
PORTKEY_CLAUDE_API_KEY=$(get_field "PORTKEY_CLAUDE_API_KEY")
ANTHROPIC_MODEL=$(get_field "ANTHROPIC_MODEL")
ANTHROPIC_SMALL_FAST_MODEL=$(get_field "ANTHROPIC_SMALL_FAST_MODEL")
ANTHROPIC_DEFAULT_MODEL=$(get_field "ANTHROPIC_DEFAULT_MODEL")

# Validate critical secrets
missing_secrets=()
[ -z "$GITHUB_TOKEN" ] && missing_secrets+=("GITHUB_TOKEN")
[ -z "$GITLAB_TOKEN" ] && missing_secrets+=("GITLAB_TOKEN")
[ -z "$VAULT_TOKEN" ] && missing_secrets+=("VAULT_TOKEN")

if [ ${#missing_secrets[@]} -gt 0 ]; then
    echo "Warning: Some critical secrets are missing from Bitwarden:"
    printf '  - %s\n' "${missing_secrets[@]}"
    echo ""
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        bw lock
        exit 1
    fi
fi

# Create .common_env.sh from template
echo "Creating ~/.common_env.sh..."

cat > ~/.common_env.sh << EOF
export EDITOR=nvim
export XDG_CONFIG_HOME="\$HOME/.config"
export GITLAB_READ_REGISTRY="$GITLAB_READ_REGISTRY"

# nvm
export NVM_DIR="\$HOME/.config/nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \\. "\$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "\$NVM_DIR/bash_completion" ] && \\. "\$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# Vault
export VAULT_TOKEN="$VAULT_TOKEN"
export VAULT_ADDR="$VAULT_ADDR"
export VAULT_NAMESPACE="$VAULT_NAMESPACE"

# RSCONNECT
export RSCONNECT_SERVER="$RSCONNECT_SERVER"
export RSCONNECT_ACCOUNT="pengg3"
export RSCONNECT_TOKEN="$RSCONNECT_TOKEN"

# PATH
export PATH=/usr/lib/rstudio/resources/app/bin/quarto/bin/tools/x86_64:\$PATH

# GITHUB TOKEN
export GITHUB_PAT="$GITHUB_PAT"
export GITHUB_TOKEN="$GITHUB_TOKEN"

# GITLAB TOKEN
export GITLAB_TOKEN="$GITLAB_TOKEN"

# OCR API - Posit Connect
export OCR_API_KEY="$OCR_API_KEY"
export DIAGNOSTIC_TOKEN="$DIAGNOSTIC_TOKEN"

# Roche Package Manager
export PACKAGEMANAGER_TOKEN="$PACKAGEMANAGER_TOKEN"
export PACKAGEMANAGER_ADDRESS="https://packages.roche.com"
export PACKAGEMANAGER_REPO="Non-Validated-Dev"

# OpenAI
export OPENAI_ACCESS_KEY="$OPENAI_ACCESS_KEY"

# Claude Code / Anthropic API (from ~/.claude/settings.json)
export ANTHROPIC_BEDROCK_BASE_URL="$ANTHROPIC_BEDROCK_BASE_URL"
export PORTKEY_CLAUDE_API_KEY="$PORTKEY_CLAUDE_API_KEY"
export ANTHROPIC_MODEL="$ANTHROPIC_MODEL"
export ANTHROPIC_SMALL_FAST_MODEL="$ANTHROPIC_SMALL_FAST_MODEL"
export ANTHROPIC_DEFAULT_MODEL="$ANTHROPIC_DEFAULT_MODEL"

# JIRA Access Token
export JIRA_API_TOKEN="$JIRA_API_TOKEN"

# SUDO Askpass
export SUDO_ASKPASS=/usr/bin/ssh-askpass
export SUDO_ASKPASS_NONINTERACTIVE=true
EOF

# Set secure permissions
chmod 600 ~/.common_env.sh

# Lock vault
bw lock

echo ""
echo "✓ Secrets successfully restored to ~/.common_env.sh"
echo "✓ File permissions set to 600 (read/write owner only)"
echo "✓ Bitwarden vault locked"
echo ""
echo "Next steps:"
echo "1. Source the file: source ~/.common_env.sh"
echo "2. Update Claude settings: update_claude_settings"
echo "3. Verify tokens are loaded: echo \$GITHUB_TOKEN | cut -c1-10"
