#!/bin/bash

# Configuration
GERRIT_HOST="review.lineageos.org"       # Replace with your Gerrit host
SSH_PORT=29418                          # Default Gerrit SSH port
LAST_CHECK_FILE="last_check.txt"        # File to store the last check timestamp
XML_URL="https://raw.githubusercontent.com/SuperiorOS/manifest/refs/heads/fifteen-los/snippets/superior.xml"  # XML URL
REPO_OWNER="SuperiorOS"                 # GitHub organization or username
EVENT_TYPE="sync_trigger"               # Custom event type for workflow

# Retrieve Gerrit username from git config
USERNAME=$(git config --global lineage.gerrit.username)

# Check if USERNAME is set, otherwise exit with an error
if [ -z "$USERNAME" ]; then
    echo -e "${RED}Error: Gerrit username is not set in git config. Please run:${NC}"
    echo -e "${CYAN}git config --global lineage.gerrit.username <your-username>${NC}"
    exit 1
fi

# Fetch GitHub token from the environment
GITHUB_PERSONAL_TOKEN="${GITHUB_PERSONAL_TOKEN:?Environment variable 'GITHUB_PERSONAL_TOKEN' is not set.}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Function to get the last check time
get_last_check_time() {
    if [ -f "$LAST_CHECK_FILE" ]; then
        cat "$LAST_CHECK_FILE"
    else
        echo "2025-01-01 00:00:00"  # Default far past timestamp
    fi
}

# Function to update the last check time
update_last_check_time() {
    echo "\"$1\"" > "$LAST_CHECK_FILE"
}

# Function to query Gerrit for new merged changes
query_gerrit() {
    local last_check="$1"
    ssh -p "$SSH_PORT" "$USERNAME@$GERRIT_HOST" gerrit query --format=JSON "status:merged branch:lineage-22.1 after:'$last_check'"
}

# Function to download and parse the XML file for repo names
get_repo_names() {
    curl -s "$XML_URL" | grep -oP '(?<=name=")[^"]+' | sed 's/^/LineageOS\/android_/'
}

# Function to trigger a GitHub workflow
trigger_github_workflow() {
    local repo_name="$1"
    echo -e "${CYAN}Triggering GitHub workflow for repo: $repo_name${NC}"
    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Authorization: Bearer $GITHUB_PERSONAL_TOKEN" \
        "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/dispatches" \
        -d "{\"event_type\":\"$EVENT_TYPE\", \"client_payload\": {\"repo_name\": \"$repo_name\"}}")

    if [ "$response" -eq 204 ]; then
        echo -e "${GREEN}Workflow triggered successfully for repo: $repo_name${NC}"
    else
        echo -e "${RED}Failed to trigger workflow for repo: $repo_name. HTTP Status: $response${NC}"
    fi

    # Add a delay to prevent overloading
    sleep 3
}

# Main script execution
main() {
    # Get the last check time
    LAST_CHECK=$(get_last_check_time)
    echo -e "${BLUE}Last check: $LAST_CHECK${NC}"

    # Query Gerrit for new merged changes
    echo -e "${YELLOW}Querying Gerrit for changes after: $LAST_CHECK${NC}"
    QUERY_RESULT=$(query_gerrit "$LAST_CHECK")

    # Parse the results
    CHANGES=$(echo "$QUERY_RESULT" | jq -c '. | select(.type != "stats")')

    if [ -z "$CHANGES" ]; then
        echo -e "${MAGENTA}No new merged changes since the last check.${NC}"
    else
        echo -e "${GREEN}New merged changes detected since the last check:${NC}"
        echo "$CHANGES" | jq

        # Get the repo names from the XML
        REPO_NAMES=$(get_repo_names)
        echo -e "${CYAN}Checking changes for the following repos:${NC}"
        echo "$REPO_NAMES"

        # Check for changes in each repo
        for REPO in $REPO_NAMES; do
            REPO_NAME=$(echo "$REPO" | sed 's|LineageOS/android_||')

            # Special case for 'manifest'
            if [ "$REPO_NAME" = "manifest" ]; then
                echo -e "${YELLOW}Special case: Checking for changes in LineageOS/android for 'manifest'${NC}"
                REPO="LineageOS/android"
            fi

            if echo "$CHANGES" | jq -r '.project' | grep -q "$REPO"; then
                echo -e "${YELLOW}Changes detected in repo: $REPO${NC}"
                trigger_github_workflow "$REPO_NAME"
            fi
        done
    fi

    # Update the last check time to the latest change timestamp
    LATEST_TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M:%S")
    echo -e "${BLUE}Updating last check time to: $LATEST_TIMESTAMP${NC}"
    update_last_check_time "$LATEST_TIMESTAMP"
}

# Run the main function
main
