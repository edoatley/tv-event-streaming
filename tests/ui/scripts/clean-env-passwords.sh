#!/bin/bash
# Script to clean password values in .env file by removing newlines
# Usage: ./clean-env-passwords.sh [env-file]

set -e

ENV_FILE="${1:-.env}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_PATH="${SCRIPT_DIR}/../${ENV_FILE}"

if [ ! -f "${ENV_PATH}" ]; then
  echo "❌ ERROR: .env file not found at: ${ENV_PATH}"
  exit 1
fi

echo "🧹 Cleaning password values in .env file..."

# Read passwords and clean them
TEST_PWD=$(grep "^TEST_USER_PASSWORD=" "${ENV_PATH}" 2>/dev/null | cut -d'=' -f2- | tr -d '\n\r' || echo "")
ADMIN_PWD=$(grep "^ADMIN_USER_PASSWORD=" "${ENV_PATH}" 2>/dev/null | cut -d'=' -f2- | tr -d '\n\r' || echo "")

if [ -z "$TEST_PWD" ] || [ -z "$ADMIN_PWD" ]; then
  echo "⚠️  Warning: One or both passwords not found in .env file"
  exit 0
fi

# Create a temporary file
TEMP_FILE=$(mktemp)

# Process the .env file line by line, cleaning password lines
while IFS= read -r line || [ -n "$line" ]; do
  if [[ "$line" =~ ^TEST_USER_PASSWORD= ]]; then
    printf 'TEST_USER_PASSWORD=%s\n' "$TEST_PWD" >> "$TEMP_FILE"
  elif [[ "$line" =~ ^ADMIN_USER_PASSWORD= ]]; then
    printf 'ADMIN_USER_PASSWORD=%s\n' "$ADMIN_PWD" >> "$TEMP_FILE"
  else
    echo "$line" >> "$TEMP_FILE"
  fi
done < "${ENV_PATH}"

# Replace the original file
mv "$TEMP_FILE" "${ENV_PATH}"

echo "✅ Password values cleaned in .env file"
echo "   TEST_USER_PASSWORD length: ${#TEST_PWD} characters"
echo "   ADMIN_USER_PASSWORD length: ${#ADMIN_PWD} characters"



