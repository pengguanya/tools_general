#!/bin/bash
# Upload secrets from ~/.common_env.sh to Bitwarden as a secure note
# This creates the "Ubuntu Dev Environment - API Tokens" secure note

set -e

echo "=== Uploading Secrets to Bitwarden ==="

# Check if bw is installed
if ! command -v bw &> /dev/null; then
    echo "Error: Bitwarden CLI not installed."
    echo "Install with: sudo snap install bw"
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq not installed."
    echo "Install with: sudo apt install jq"
    exit 1
fi

# Check if .common_env.sh exists
if [ ! -f "$HOME/.common_env.sh" ]; then
    echo "Error: ~/.common_env.sh not found"
    exit 1
fi

# Login if not already logged in
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

# Unlock vault
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

# Create or get folder
echo "Setting up folder in Bitwarden..."
FOLDER_NAME="Ubuntu Migration"

# Check if folder already exists
EXISTING_FOLDER=$(bw list folders --search "$FOLDER_NAME" 2>/dev/null || echo "[]")
FOLDER_ID=$(echo "$EXISTING_FOLDER" | jq -r '.[0].id // empty')

if [ -z "$FOLDER_ID" ] || [ "$FOLDER_ID" = "null" ]; then
    echo "Creating folder: $FOLDER_NAME"
    FOLDER_JSON=$(jq -n --arg name "$FOLDER_NAME" '{name: $name}')
    FOLDER_RESULT=$(echo "$FOLDER_JSON" | bw encode | bw create folder --session "$BW_SESSION" 2>&1)
    if [ $? -eq 0 ]; then
        FOLDER_ID=$(echo "$FOLDER_RESULT" | jq -r '.id')
        echo "✓ Folder created: $FOLDER_ID"
    else
        echo "Error creating folder: $FOLDER_RESULT"
        echo "Continuing without folder..."
        FOLDER_ID="null"
    fi
else
    echo "✓ Using existing folder: $FOLDER_NAME (ID: $FOLDER_ID)"
fi

# Check if item already exists
echo "Checking if secure note already exists..."
EXISTING_ITEM=$(bw list items --search "Ubuntu Dev Environment - API Tokens" 2>/dev/null || echo "[]")
ITEM_COUNT=$(echo "$EXISTING_ITEM" | jq '. | length')

if [ "$ITEM_COUNT" -gt 0 ]; then
    echo "⚠️  Warning: Secure note 'Ubuntu Dev Environment - API Tokens' already exists!"
    echo "   Found $ITEM_COUNT item(s) with this name."
    echo ""
    read -p "Do you want to create a new item anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted. Use the Bitwarden web UI to update the existing item."
        bw lock
        exit 0
    fi
fi

# Parse ~/.common_env.sh and extract all export statements
echo ""
echo "Extracting secrets from ~/.common_env.sh..."

# Create an array to hold field definitions
declare -a FIELDS=()

# Function to add a field
add_field() {
    local name="$1"
    local value="$2"

    # Skip empty values
    if [ -z "$value" ]; then
        return
    fi

    # Create JSON field object
    local field_json=$(jq -n \
        --arg name "$name" \
        --arg value "$value" \
        '{name: $name, value: $value, type: 0}')

    FIELDS+=("$field_json")
}

# Read and parse .common_env.sh
while IFS= read -r line; do
    # Skip comments and empty lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$line" ]] && continue

    # Match export statements
    if [[ "$line" =~ ^export[[:space:]]+([A-Z_]+)=\"?([^\"]*)\"?$ ]]; then
        var_name="${BASH_REMATCH[1]}"
        var_value="${BASH_REMATCH[2]}"

        # Skip non-secret variables
        case "$var_name" in
            EDITOR|XDG_CONFIG_HOME|NVM_DIR|PATH|RSCONNECT_ACCOUNT|PACKAGEMANAGER_ADDRESS|PACKAGEMANAGER_REPO|SUDO_ASKPASS|SUDO_ASKPASS_NONINTERACTIVE)
                continue
                ;;
        esac

        echo "  Found: $var_name"
        add_field "$var_name" "$var_value"
    fi
done < "$HOME/.common_env.sh"

echo ""
echo "Found ${#FIELDS[@]} secrets to upload"

# Build JSON array of fields
FIELDS_JSON="[]"
for field in "${FIELDS[@]}"; do
    FIELDS_JSON=$(echo "$FIELDS_JSON" | jq --argjson field "$field" '. + [$field]')
done

# Create secure note JSON
if [ "$FOLDER_ID" = "null" ] || [ -z "$FOLDER_ID" ]; then
    FOLDER_ID_ARG="null"
else
    FOLDER_ID_ARG="\"$FOLDER_ID\""
fi

SECURE_NOTE_JSON=$(jq -n \
    --arg name "Ubuntu Dev Environment - API Tokens" \
    --argjson fields "$FIELDS_JSON" \
    --argjson folderId "$FOLDER_ID_ARG" \
    '{
        organizationId: null,
        folderId: $folderId,
        type: 2,
        name: $name,
        notes: "API tokens and secrets for Ubuntu development environment.\n\nGenerated automatically from ~/.common_env.sh\nUse restore_secrets_from_bitwarden script to restore after system migration.\n\nLast updated: '"$(date -u +"%Y-%m-%d %H:%M:%S UTC")"'",
        favorite: false,
        fields: $fields,
        secureNote: {
            type: 0
        },
        reprompt: 0
    }')

# Create the item in Bitwarden
echo ""
echo "Creating secure note in Bitwarden..."
RESULT=$(echo "$SECURE_NOTE_JSON" | bw encode | bw create item --session "$BW_SESSION" 2>&1)

if [ $? -eq 0 ]; then
    ITEM_ID=$(echo "$RESULT" | jq -r '.id')
    echo ""
    echo "=========================================="
    echo " ✓ SUCCESS!"
    echo "=========================================="
    echo ""
    echo "Secure note created successfully!"
    echo "Folder: $FOLDER_NAME"
    echo "Item ID: $ITEM_ID"
    echo "Item Name: Ubuntu Dev Environment - API Tokens"
    echo "Fields: ${#FIELDS[@]} secrets"
    echo ""
    echo "You can view it in Bitwarden:"
    echo "  Web: https://vault.bitwarden.com (look in '$FOLDER_NAME' folder)"
    echo "  CLI: bw get item $ITEM_ID"
    echo ""
else
    echo ""
    echo "=========================================="
    echo " ✗ ERROR"
    echo "=========================================="
    echo ""
    echo "Failed to create secure note:"
    echo "$RESULT"
    echo ""
    bw lock
    exit 1
fi

# Lock vault
bw lock

echo "✓ Bitwarden vault locked"
echo ""
echo "Next steps:"
echo "1. Verify the item in Bitwarden web UI"
echo "2. Test restore with: restore_secrets_from_bitwarden"
echo "3. Continue with backup procedures"
