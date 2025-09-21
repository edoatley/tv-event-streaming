#!/bin/bash

# This script inspects the DynamoDB table to provide a summary of its contents,
# which is useful for debugging data ingestion and API responses.

set -e
set -o pipefail

# --- Configuration ---
STACK_NAME="uktv-event-streaming-app"
PROFILE="streaming"
REGION="eu-west-2"

# --- Prefixes (should match web_api.py) ---
SOURCE_PREFIX="source:"
GENRE_PREFIX="genre:"
USER_PREF_PREFIX="userpref:"

# --- Helper Functions ---
log() {
    echo "✅ $1"
}

info() {
    echo "   - $1"
}

error() {
    echo "❌ ERROR: $1" >&2
    exit 1
}

# --- Main Script ---
echo "🚀 Starting DynamoDB Inspector..."

# Step 0: Prerequisite check
if ! command -v jq &> /dev/null; then
    error "jq is not installed. Please install it to run these tests (e.g., 'brew install jq' or 'sudo apt-get install jq')."
fi
log "Prerequisite check passed (jq is installed)."

# Step 1: Check AWS session
log "Step 1: Checking AWS SSO session for profile: ${PROFILE}..."
if ! aws sts get-caller-identity --profile "${PROFILE}" > /dev/null 2>&1; then
    echo "⚠️ AWS SSO session expired or not found. Please log in."
    aws sso login --profile "${PROFILE}"
    if ! aws sts get-caller-identity --profile "${PROFILE}" > /dev/null 2>&1; then
        error "AWS login failed. Please check your configuration. Aborting."
    fi
fi
log "AWS SSO session is active."

# Step 2: Fetch Stack Outputs
log "Step 2: Fetching required outputs from stack '$STACK_NAME'..."
TABLE_NAME=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='ProgrammesTable'].OutputValue" --output text --profile "$PROFILE" --region "$REGION")
USER_POOL_ID=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='UserPoolId'].OutputValue" --output text --profile "$PROFILE" --region "$REGION")
TEST_USERNAME=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='TestUsername'].OutputValue" --output text --profile "$PROFILE" --region "$REGION")

if [ -z "$TABLE_NAME" ] || [ -z "$USER_POOL_ID" ] || [ -z "$TEST_USERNAME" ]; then
    error "Failed to retrieve one or more required stack outputs. Aborting."
fi
log "Successfully fetched stack outputs."
info "Table Name: $TABLE_NAME"
info "Test Username: $TEST_USERNAME"

# Step 3: Get Test User's 'sub' attribute from Cognito
log "Step 3: Fetching 'sub' for test user '$TEST_USERNAME'..."
USER_SUB=$(aws cognito-idp list-users --user-pool-id "$USER_POOL_ID" --filter "email = \"$TEST_USERNAME\"" --query "Users[0].Attributes[?Name=='sub'].Value" --output text --profile "$PROFILE" --region "$REGION")

if [ -z "$USER_SUB" ]; then
    error "Could not find 'sub' for user '$TEST_USERNAME'. Make sure the user exists in the pool."
fi
log "Found user 'sub': $USER_SUB"

# Step 4: Scan DynamoDB and generate report
log "Step 4: Scanning table '$TABLE_NAME' to generate report..."
echo "(Note: A full scan can be slow and costly on large tables. This is for development/debugging.)"
ALL_ITEMS=$(aws dynamodb scan --table-name "$TABLE_NAME" --projection-expression "PK, SK" --profile "$PROFILE" --region "$REGION")
log "Scan complete. Analyzing results..."

# --- Analysis ---
echo ""
echo "📊 DynamoDB Data Summary 📊"
echo "--------------------------------------------------"

# Count Sources and Genres by mimicking the logic in get_ref_data
SOURCE_COUNT=$(echo "$ALL_ITEMS" | jq --arg p "$SOURCE_PREFIX" '[.Items[] | .PK.S | select(startswith($p)) | select((split(":") | length) == 2)] | length')
echo "Number of Sources: $SOURCE_COUNT"

GENRE_COUNT=$(echo "$ALL_ITEMS" | jq --arg p "$GENRE_PREFIX" '[.Items[] | .PK.S | select(startswith($p)) | select((split(":") | length) == 2)] | length')
echo "Number of Genres: $GENRE_COUNT"

echo "--------------------------------------------------"

# Get User Preferences
USER_PREF_PK="${USER_PREF_PREFIX}${USER_SUB}"
USER_PREFS=$(aws dynamodb query --table-name "$TABLE_NAME" --key-condition-expression "PK = :pk" --expression-attribute-values '{":pk":{"S":"'"$USER_PREF_PK"'"}}' --projection-expression "SK" --profile "$PROFILE" --region "$REGION")

PREFERRED_SOURCES=$(echo "$USER_PREFS" | jq --arg p "$SOURCE_PREFIX" '[.Items[] | .SK.S | select(startswith($p))] | map(split(":")[1])')
PREFERRED_GENRES=$(echo "$USER_PREFS" | jq --arg p "$GENRE_PREFIX" '[.Items[] | .SK.S | select(startswith($p))] | map(split(":")[1])')

echo "Preferences for user: $TEST_USERNAME"
info "Preferred Source IDs: $(echo "$PREFERRED_SOURCES" | jq -c .)"
info "Preferred Genre IDs:  $(echo "$PREFERRED_GENRES" | jq -c .)"

echo "--------------------------------------------------"

# Count titles by source/genre combination (the manual index items)
echo "Title counts per Source/Genre combination:"
TITLE_INDEX_COUNTS=$(echo "$ALL_ITEMS" | jq '[.Items[] | .PK.S | select(contains(":genre:"))] | group_by(.) | map({combination: .[0], count: length}) | sort_by(.count) | reverse')

if [ "$(echo "$TITLE_INDEX_COUNTS" | jq 'length')" -eq 0 ]; then
    info "No source/genre index items found. The 'UserPrefsTitleIngestionApp' may not have run."
else
    # Display top 20 results for brevity
    echo "$TITLE_INDEX_COUNTS" | jq -r '.[:20] | .[] | "   - \(.combination): \(.count) titles"'
    if [ "$(echo "$TITLE_INDEX_COUNTS" | jq 'length')" -gt 20 ]; then
        info "...and more."
    fi
fi

echo "--------------------------------------------------"

# Count unenriched titles
echo "Unenriched Titles Summary:"
UNENRICHED_COUNT=$(aws dynamodb scan --table-name "$TABLE_NAME" \
    --filter-expression "begins_with(PK, :title_prefix) AND (attribute_not_exists(#d.poster) OR attribute_not_exists(#d.plot_overview) OR #d.poster = :empty_string)" \
    --expression-attribute-names '{"#d": "data"}' \
    --expression-attribute-values '{":title_prefix": {"S": "title:"}, ":empty_string": {"S": ""}}' \
    --select "COUNT" --query "Count" --profile "$PROFILE" --region "$REGION")

info "Found ${UNENRICHED_COUNT} titles missing a poster or plot."

if [ "$UNENRICHED_COUNT" -gt 0 ]; then
    info "Example unenriched title IDs:"
    aws dynamodb scan --table-name "$TABLE_NAME" \
        --filter-expression "begins_with(PK, :title_prefix) AND (attribute_not_exists(#d.poster) OR attribute_not_exists(#d.plot_overview) OR #d.poster = :empty_string)" \
        --expression-attribute-names '{"#d": "data"}' \
        --expression-attribute-values '{":title_prefix": {"S": "title:"}, ":empty_string": {"S": ""}}' \
        --projection-expression "PK" --page-size 5 --profile "$PROFILE" --region "$REGION" | jq -r '.Items[].PK.S | "     - \(.)"'
fi

echo "--------------------------------------------------"
echo "🎉 Inspection complete."