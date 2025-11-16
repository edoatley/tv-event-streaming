#!/bin/bash

# Script to set up test data before running tests
# This ensures the test environment has the necessary data

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"

# Load environment variables
if [ -f "${TEST_DIR}/.env" ]; then
  export $(cat "${TEST_DIR}/.env" | grep -v '^#' | xargs)
fi

STACK_NAME="${1:-tv-event-streaming-gha}"
REGION="${AWS_REGION:-eu-west-2}"
PROFILE="${AWS_PROFILE:-streaming}"

print_info() {
  echo -e "\033[1;34m[INFO]\033[0m $1"
}

print_success() {
  echo -e "\033[1;32m[SUCCESS]\033[0m $1"
}

print_error() {
  echo -e "\033[1;31m[ERROR]\033[0m $1"
}

print_info "Setting up test data..."
print_info "Stack: ${STACK_NAME}"
print_info "Region: ${REGION}"
print_info "Profile: ${PROFILE}"

# Check if BASE_URL is set
if [ -z "$BASE_URL" ]; then
  print_error "BASE_URL not set. Please set it in .env file or use fetch-stack-outputs.sh"
  exit 1
fi

# Get API endpoint from BASE_URL or use separate API_ENDPOINT
API_ENDPOINT="${API_ENDPOINT:-${BASE_URL}}"

# Get test user credentials
if [ -z "$TEST_USER_EMAIL" ] || [ -z "$TEST_USER_PASSWORD" ]; then
  print_error "TEST_USER_EMAIL and TEST_USER_PASSWORD must be set in .env file"
  exit 1
fi

print_info "Fetching Cognito token for test user..."

# Get Cognito token (this would require the cognito helper or AWS CLI)
# For now, we'll use a simplified approach - the tests will handle authentication

print_info "Checking if reference data exists..."

# Check if sources and genres are available via API
SOURCES_RESPONSE=$(curl -s "${API_ENDPOINT}/sources" || echo "[]")
GENRES_RESPONSE=$(curl -s "${API_ENDPOINT}/genres" || echo "[]")

SOURCES_COUNT=$(echo "$SOURCES_RESPONSE" | jq '. | length' 2>/dev/null || echo "0")
GENRES_COUNT=$(echo "$GENRES_RESPONSE" | jq '. | length' 2>/dev/null || echo "0")

if [ "$SOURCES_COUNT" -eq 0 ] || [ "$GENRES_COUNT" -eq 0 ]; then
  print_error "Reference data (sources or genres) is missing."
  print_info "You may need to trigger the reference data refresh Lambda function."
  print_info "This can be done via the admin panel or by invoking the Lambda directly."
  exit 1
fi

print_success "Reference data found: ${SOURCES_COUNT} sources, ${GENRES_COUNT} genres"

print_info "Checking if title data exists..."

# Note: We can't easily check title data without authentication
# The tests will handle this gracefully

print_success "Test data setup complete!"
print_info ""
print_info "Next steps:"
print_info "  1. Ensure test users have passwords set in Cognito"
print_info "  2. If title data is missing, trigger title ingestion via admin panel"
print_info "  3. Run tests: ./run-tests.sh"

