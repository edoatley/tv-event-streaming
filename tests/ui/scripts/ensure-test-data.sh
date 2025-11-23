#!/bin/bash

# Script to ensure test data exists (idempotent)
# This script checks and creates test data if needed

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

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

print_warn() {
  echo -e "\033[1;33m[WARN]\033[0m $1"
}

print_info "Ensuring test data exists..."

# Check if BASE_URL is set
if [ -z "$BASE_URL" ]; then
  print_warn "BASE_URL not set. Skipping API checks."
  exit 0
fi

API_ENDPOINT="${API_ENDPOINT:-${BASE_URL}}"

# Check reference data
print_info "Checking reference data..."

SOURCES_RESPONSE=$(curl -s "${API_ENDPOINT}/sources" 2>/dev/null || echo "[]")
GENRES_RESPONSE=$(curl -s "${API_ENDPOINT}/genres" 2>/dev/null || echo "[]")

SOURCES_COUNT=$(echo "$SOURCES_RESPONSE" | jq -r '. | length' 2>/dev/null || echo "0")
GENRES_COUNT=$(echo "$GENRES_RESPONSE" | jq -r '. | length' 2>/dev/null || echo "0")

if [ "$SOURCES_COUNT" -eq "0" ]; then
  print_warn "No sources found. Reference data may need to be refreshed."
  print_info "You can trigger this via the admin panel or Lambda function."
else
  print_success "Found ${SOURCES_COUNT} sources"
fi

if [ "$GENRES_COUNT" -eq "0" ]; then
  print_warn "No genres found. Reference data may need to be refreshed."
  print_info "You can trigger this via the admin panel or Lambda function."
else
  print_success "Found ${GENRES_COUNT} genres"
fi

# Check if test users exist (requires AWS CLI)
if command -v aws &> /dev/null; then
  print_info "Checking test users in Cognito..."
  
  if [ -n "$COGNITO_USER_POOL_ID" ]; then
    # Check if test user exists
    if aws cognito-idp admin-get-user \
      --user-pool-id "$COGNITO_USER_POOL_ID" \
      --username "$TEST_USER_EMAIL" \
      --profile "$PROFILE" \
      --region "$REGION" \
      &>/dev/null; then
      print_success "Test user exists: ${TEST_USER_EMAIL}"
    else
      print_warn "Test user not found: ${TEST_USER_EMAIL}"
      print_info "User should be created by CloudFormation stack."
    fi
    
    # Check if admin user exists
    if [ -n "$ADMIN_USER_EMAIL" ]; then
      if aws cognito-idp admin-get-user \
        --user-pool-id "$COGNITO_USER_POOL_ID" \
        --username "$ADMIN_USER_EMAIL" \
        --profile "$PROFILE" \
        --region "$REGION" \
        &>/dev/null; then
        print_success "Admin user exists: ${ADMIN_USER_EMAIL}"
      else
        print_warn "Admin user not found: ${ADMIN_USER_EMAIL}"
        print_info "User should be created by CloudFormation stack."
      fi
    fi
  else
    print_warn "COGNITO_USER_POOL_ID not set. Skipping user checks."
  fi
else
  print_warn "AWS CLI not found. Skipping user checks."
fi

print_success "Test data check complete!"

