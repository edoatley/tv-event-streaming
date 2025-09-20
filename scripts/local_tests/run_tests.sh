#!/bin/bash
##########################################################
# Script to use sam invoke and run all the tests we have
##########################################################

# Exit on error, treat unset variables as an error
set -euo pipefail

# Get the script directory and the directory from which to invoke the sam calls
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
#SCRIPT_DIR=${0:a:h}
PROJECT_ROOT=$(cd "${SCRIPT_DIR}/../../.." && pwd)
ENV_DIR="${PROJECT_ROOT}/env"
EVENT_DIR="${PROJECT_ROOT}/events"
PROFILE_NAME="streaming"
DEBUG=false

# --- Source Helper Functions ---
# shellcheck source=resources/test_helpers.sh
source "${SCRIPT_DIR}/test_helpers.sh"

# --- Argument Parsing for Debug Flag ---
if [[ "${1:-}" == "-d" || "${1:-}" == "--debug" ]]; then
    DEBUG=true
    print_info "Debug mode enabled. Full 'sam local invoke' output will be shown."
fi
export DEBUG

# --- Check for AWS SSO Login ---

print_info "Checking AWS SSO session for profile: ${PROFILE_NAME}..."
# The >/dev/null 2>&1 silences the command's output on success
if ! aws sts get-caller-identity --profile "${PROFILE_NAME}" > /dev/null 2>&1; then
    print_info "AWS SSO session expired or not found. Please log in."
    # This command is interactive and will open a browser
    aws sso login --profile "${PROFILE_NAME}"

    # Re-check after login attempt to ensure it was successful before proceeding
    if ! aws sts get-caller-identity --profile "${PROFILE_NAME}" > /dev/null 2>&1; then
        print_error "AWS login failed. Please check your configuration. Aborting."
        exit 1
    fi
    print_success "✅ AWS login successful."
else
    print_success "✅ AWS SSO session is active."
fi

# --- Main Execution ---
print_info "Moving to SAM project root directory: ${PROJECT_ROOT}"
cd "${PROJECT_ROOT}" || exit

# Run a build before testing to ensure all artifacts are up-to-date
print_info "Running 'sam build' to prepare artifacts..."
sam build

# Run specialist tests for each function (Format: "FunctionName EventFile EnvFile")
declare -a tests=(
 "PeriodicReferenceApp/PeriodicReferenceFunction periodic_reference.json periodic_reference.json"
 "UserPreferencesApp/UserPreferencesFunction user_prefs_get_sources.json user_preferences.json"
 "UserPreferencesApp/UserPreferencesFunction user_prefs_get_genres.json user_preferences.json"
 "UserPreferencesApp/UserPreferencesFunction user_prefs_put_preferences.json user_preferences.json"
 "UserPreferencesApp/UserPreferencesFunction user_prefs_get_preferences.json user_preferences.json"
)

print_info "Running local tests..."
for test_case in "${tests[@]}"; do
  read -r -a test_params <<< "$test_case"
  function_name="${test_params[0]}"
  event_file="${EVENT_DIR}/${test_params[1]}"
  env_file="${ENV_DIR}/${test_params[2]}"
  run_test "$function_name" "$event_file" "$env_file"
done

print_info "Running local integration test..."
bash "${SCRIPT_DIR}/test_e2e.sh"

print_info "Running local enrichment test..."
bash "${SCRIPT_DIR}/test_enrichment.sh"

print_info "================================="
print_success "All local tests passed successfully!"
print_info "================================="
