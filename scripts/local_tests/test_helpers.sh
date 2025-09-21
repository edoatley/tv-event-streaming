#!/bin/bash
# Helper functions for the local test execution script.
# This file is intended to be sourced, not executed directly.

DOCKER_NETWORK="event-streaming-app_podman"

# Helper functions to print colored text
print_info() {
    printf "\n\033[1;34m%s\033[0m\n" "$1"
}

print_success() {
    printf "\033[1;32m%s\033[0m\n" "$1"
}

print_error() {
    printf "\033[1;31m%s\033[0m\n" "$1" >&2
}

# --- Reusable Test Runner Function ---
# Usage: run_test "FunctionName" "path/to/event.json" "path/to/env.json"
# Depends on a `DEBUG` variable being set in the calling script.
run_test() {
    local function_name="$1"
    local event_file="$2"
    local env_file="$3"
    local output_text
    local exit_code

    event_filename=$(basename "${event_file}")
    print_info "===== Running Test: ${function_name} (${event_filename})  ====="

    # The '|| true' prevents 'set -e' from exiting the script immediately on failure,
    # allowing us to capture the exit code and handle the error gracefully.
    output_text=$(sam local invoke "${function_name}" \
      --event "${event_file}" \
      --env-vars "${env_file}" \
      --docker-network "${DOCKER_NETWORK}" < /dev/null 2>&1) || true
    exit_code=$?

    # If in debug mode, print the full output immediately for context
    if [ "${DEBUG:-false}" = true ]; then
        echo "--- Full 'sam local invoke' output (Debug Mode) ---"
        echo "${output_text}"
        echo "---------------------------------------------------"
    fi

    # 1. Check for command failure (non-zero exit code from sam)
    if [ $exit_code -ne 0 ]; then
        print_error "TEST FAILED: 'sam local invoke' exited with code ${exit_code}."
        # Don't print output again if already in debug mode
        if [ "${DEBUG:-false}" = false ]; then
            echo "${output_text}"
        fi
        exit 1
    fi

    # 2. Check for application error (non-2xx status code in the JSON response)
    local result_json
    result_json=$(echo "${output_text}" | tail -n 1)

    if ! echo "${result_json}" | jq . > /dev/null 2>&1; then
        print_error "TEST FAILED: The function did not return valid JSON."
        if [ "${DEBUG:-false}" = false ]; then
            echo "--- Full output: ---"
            echo "${output_text}"
        fi
        exit 1
    fi

    local status_code
    status_code=$(echo "${result_json}" | jq -r '.statusCode // 0')

    if [[ "$status_code" -lt 200 || "$status_code" -ge 300 ]]; then
        print_error "TEST FAILED: Function returned status code ${status_code}."
        if [ "${DEBUG:-false}" = false ]; then
            echo "--- Full output: ---"
            echo "${output_text}"
        fi
        exit 1
    fi

    # 3. Check for logged errors
    if echo "${output_text}" | grep -q "\[ERROR\]"; then
        print_error "TEST FAILED: Found [ERROR] in function logs."
        if [ "${DEBUG:-false}" = false ]; then
            echo "--- Full output: ---"
            echo "${output_text}"
        fi
        exit 1
    fi

    print_success "✅ TEST PASSED: ${function_name}"
}