#!/bin/bash
#
# Script Name: hub2lab.sh
# Description: Imports a GitHub repository into GitLab using their Import API
#              with personal access tokens for both services.
# Usage: GITLAB_TOKEN=xxx GITHUB_TOKEN=yyy ./hub2lab.sh <github_user> <repo> [new_gitlab_name]
# Requirements: curl, jq, GitLab personal access token, GitHub personal access token
# Example: GITLAB_TOKEN=glpat... GITHUB_TOKEN=ghp... ./hub2lab.sh pengguanya sollist
#
# === FUNCTIONS ===
show_help() {
  echo "Usage: $0 <github_username> <github_repo_name> [new_gitlab_project_name]"
  echo
  echo "Imports a GitHub repository into your GitLab account via the GitLab Import API."
  echo
  echo "Required Environment Variables:"
  echo "  GITLAB_TOKEN       Your GitLab personal access token"
  echo "  GITHUB_TOKEN       Your GitHub personal access token"
  echo
  echo "Positional Arguments:"
  echo "  github_username            Your GitHub username (e.g. pengguanya)"
  echo "  github_repo_name           Name of your GitHub repository (e.g. sollist)"
  echo "  new_gitlab_project_name    (Optional) Desired project name in GitLab (default: same as github_repo_name)"
  echo
  echo "Example:"
  echo "  GITLAB_TOKEN=glpat-xxx GITHUB_TOKEN=ghp-xxx \\"
  echo "  $0 pengguanya sollist"
  echo
  echo "  # Or with custom GitLab project name:"
  echo "  $0 pengguanya sollist sollist-imported"
  exit 1
}

# === VALIDATION ===
if [[ "$1" == "-h" || "$1" == "--help" || $# -lt 2 ]]; then
  show_help
fi

if [[ -z "$GITLAB_TOKEN" || -z "$GITHUB_TOKEN" ]]; then
  echo "❌ Error: GITLAB_TOKEN and GITHUB_TOKEN environment variables must be set."
  show_help
fi

# === INPUT VARIABLES ===
GITHUB_USER="$1"
GITHUB_REPO="$2"
NEW_NAME="${3:-$GITHUB_REPO}"  # Default to github repo name if not provided
TARGET_NAMESPACE="pengg3"
GITLAB_URL="https://code.roche.com"

# === FETCH GITHUB REPO ID ===
echo "🔍 Fetching GitHub repository ID for ${GITHUB_USER}/${GITHUB_REPO}..."

GITHUB_REPO_ID=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
  "https://api.github.com/repos/${GITHUB_USER}/${GITHUB_REPO}" | jq '.id')

if [[ "$GITHUB_REPO_ID" == "null" || -z "$GITHUB_REPO_ID" ]]; then
  echo "❌ Failed to fetch GitHub repo ID. Check repository name and access token."
  exit 1
fi

echo "✅ GitHub repo ID: $GITHUB_REPO_ID"

# === IMPORT REPO TO GITLAB ===
echo "🚀 Importing GitHub repo ${GITHUB_USER}/${GITHUB_REPO} into GitLab as ${NEW_NAME}..."

curl --request POST \
  --url "${GITLAB_URL}/api/v4/import/github" \
  --header "Content-Type: application/json" \
  --header "Authorization: Bearer ${GITLAB_TOKEN}" \
  --data "{
    \"personal_access_token\": \"${GITHUB_TOKEN}\",
    \"repo_id\": ${GITHUB_REPO_ID},
    \"target_namespace\": \"${TARGET_NAMESPACE}\",
    \"new_name\": \"${NEW_NAME}\"
  }"

