#!/bin/bash
################################################################
# Specialist integration test for TitleEnrichmentFunction
#
# This test performs the following steps:
# 1. Setup: Creates a dummy canonical title record in DynamoDB.
# 2. Execute: Invokes the Lambda function with a simulated
#    DynamoDB Stream event.
# 3. Verify: Checks that the DynamoDB item was updated with
#    enriched data.
# 4. Teardown: Cleans up the dummy data from DynamoDB.
################################################################
DEBUG=true
# Exit on error, treat unset variables as an error
set -euo pipefail

# --- Configuration ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
#SCRIPT_DIR=${0:a:h}
PROJECT_ROOT=$(cd "${SCRIPT_DIR}/../../.." && pwd)

# Source the helper functions for colored output
# shellcheck source=test_helpers.sh
source "${SCRIPT_DIR}/test_helpers.sh"

# --- LocalStack & AWS Configuration ---
PROFILE_NAME="streaming"
ENDPOINT_URL="http://localhost:4566"
TABLE_NAME="UKTVProgrammesLocal"
DOCKER_NETWORK="event-streaming-app_podman"

# --- Test Data ---
# Use a known, valid title ID for a real API call
TEST_TITLE_ID="3226810" # Sakamoto Days

# --- Helper Functions ---
# Sets up the prerequisite data in DynamoDB
setup_title_record() {
    print_info "Setting up prerequisite title record in DynamoDB..."
    aws --profile "${PROFILE_NAME}" --endpoint-url "${ENDPOINT_URL}" \
        dynamodb put-item \
        --table-name "${TABLE_NAME}" \
        --item "{\"PK\": {\"S\": \"title:${TEST_TITLE_ID}\"}, \"SK\": {\"S\": \"record\"}, \"data\": {\"M\": {}}}"
    print_success "✅ Setup complete."
}

# Cleans up the data from DynamoDB
teardown_title_record() {
    print_info "Cleaning up test title record from DynamoDB..."
    aws --profile "${PROFILE_NAME}" --endpoint-url "${ENDPOINT_URL}" \
        dynamodb delete-item \
        --table-name "${TABLE_NAME}" \
        --key "{\"PK\": {\"S\": \"title:${TEST_TITLE_ID}\"}, \"SK\": {\"S\": \"record\"}}" > /dev/null
    print_success "✅ Teardown complete."
}

# Verifies that the item was enriched
verify_enrichment() {
    print_info "Verifying that the DynamoDB item was enriched..."
    local item_json
    item_json=$(aws dynamodb get-item --profile "${PROFILE_NAME}" --endpoint-url "${ENDPOINT_URL}" \
        --table-name "${TABLE_NAME}" --key "{\"PK\": {\"S\": \"title:${TEST_TITLE_ID}\"}, \"SK\": {\"S\": \"record\"}}")

    # Check if the item was found at all
    if ! echo "${item_json}" | jq -e '.Item' > /dev/null; then
        print_error "❌ VERIFICATION FAILED: Could not find item with PK title:${TEST_TITLE_ID}."
        echo "Response from get-item:"
        echo "${item_json}" | jq
        exit 1
    fi

    # Extract the 'data' map for easier validation and print it
    local data_map
    data_map=$(echo "${item_json}" | jq '.Item.data.M')

    print_info "  - Enriched data found:"
    echo "${data_map}" | jq .

    # Validate that specific enriched fields exist and are not the default 'N/A'
    if echo "${data_map}" | jq -e '(.plot_overview.S and .plot_overview.S != "N/A") and (.poster.S and .poster.S != "N/A") and .user_rating.N' > /dev/null; then
        print_success "✅ VERIFICATION PASSED: Item was successfully enriched with plot, poster, and rating."
    else
        print_error "❌ VERIFICATION FAILED: One or more enriched fields are missing or have default values."
        exit 1
    fi
}

# --- Main Execution ---
trap teardown_title_record EXIT

print_info "===== START: Integration Test for TitleEnrichmentFunction ====="

print_info "--> STEP 1: Setting up test data..."
setup_title_record

print_info "--> STEP 2: Invoking the enrichment Lambda..."
# We must be in the project root for sam to find the templates and build artifacts
cd "${PROJECT_ROOT}"

# Use the generic run_test helper for invocation and basic checks
run_test \
  "TitleEnrichmentApp/TitleEnrichmentFunction" \
  "${PROJECT_ROOT}/events/title_enrichment_event.json" \
  "${PROJECT_ROOT}/env/title_enrichment.json"

print_info "--> STEP 3: Verifying the enrichment in DynamoDB..."
verify_enrichment

print_success "===== ✅ Enrichment Test Passed! ====="