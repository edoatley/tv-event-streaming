#!/bin/bash
# Utility script to extract user information from config/users.json
# Usage: source this script or call functions directly

CONFIG_FILE="${1:-config/users.json}"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config file not found: $CONFIG_FILE" >&2
    exit 1
fi

# Get all usernames (comma-separated)
get_all_usernames() {
    jq -r '.users[].email' "$CONFIG_FILE" | tr '\n' ',' | sed 's/,$//'
}

# Get admin usernames (comma-separated)
get_admin_usernames() {
    jq -r '.users[] | select(.type == "admin") | .email' "$CONFIG_FILE" | tr '\n' ',' | sed 's/,$//'
}

# Get standard usernames (comma-separated)
get_standard_usernames() {
    jq -r '.users[] | select(.type == "standard") | .email' "$CONFIG_FILE" | tr '\n' ',' | sed 's/,$//'
}

# Get first test user (for backward compatibility)
get_test_username() {
    jq -r '.users[] | select(.type == "standard") | .email' "$CONFIG_FILE" | head -1
}

# Get first admin user (for backward compatibility)
get_admin_username() {
    jq -r '.users[] | select(.type == "admin") | .email' "$CONFIG_FILE" | head -1
}

# Main execution - if script is run directly, output the values
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${2:-all}" in
        all)
            get_all_usernames
            ;;
        admin)
            get_admin_usernames
            ;;
        standard)
            get_standard_usernames
            ;;
        test)
            get_test_username
            ;;
        admin-first)
            get_admin_username
            ;;
        *)
            echo "Usage: $0 <config-file> [all|admin|standard|test|admin-first]"
            exit 1
            ;;
    esac
fi




