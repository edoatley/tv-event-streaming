#!/bin/bash

# Script to run UI tests
# Usage: ./run-tests.sh [options]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${TEST_DIR}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# Check if .env file exists
if [ ! -f "${TEST_DIR}/.env" ]; then
  print_warn ".env file not found. Creating from template..."
  if [ -f "${TEST_DIR}/.env.example" ]; then
    cp "${TEST_DIR}/.env.example" "${TEST_DIR}/.env"
  elif [ -f "${TEST_DIR}/env.example" ]; then
    cp "${TEST_DIR}/env.example" "${TEST_DIR}/.env"
  else
    print_error ".env.example or env.example not found. Cannot create .env file."
    exit 1
  fi
  print_warn "Please edit .env file and set required values before running tests."
  print_warn "You can also use ./scripts/fetch-stack-outputs.sh to populate some values."
  exit 1
fi

# Check if node_modules exists
if [ ! -d "${TEST_DIR}/node_modules" ]; then
  print_info "Installing dependencies..."
  npm install
fi

# Check if Playwright browsers are installed
if [ ! -d "${TEST_DIR}/node_modules/@playwright/test" ]; then
  print_info "Installing Playwright browsers..."
  npx playwright install --with-deps
fi

# Parse arguments
RUN_MODE="test"
BROWSER=""
SPEC=""
HEADED=false
DEBUG=false
UI=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --headed)
      HEADED=true
      shift
      ;;
    --debug)
      DEBUG=true
      shift
      ;;
    --ui)
      UI=true
      shift
      ;;
    --browser=*)
      BROWSER="${1#*=}"
      shift
      ;;
    --spec=*)
      SPEC="${1#*=}"
      shift
      ;;
    --help)
      echo "Usage: ./run-tests.sh [options]"
      echo ""
      echo "Options:"
      echo "  --headed              Run tests in headed mode (show browser)"
      echo "  --debug               Run tests in debug mode"
      echo "  --ui                  Run tests in UI mode (interactive)"
      echo "  --browser=<browser>   Run tests for specific browser (chromium, firefox, webkit)"
      echo "  --spec=<file>         Run specific test file"
      echo "  --help                 Show this help message"
      exit 0
      ;;
    *)
      print_error "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Build command
CMD="npx playwright test"

if [ "$HEADED" = true ]; then
  CMD="${CMD} --headed"
elif [ "$DEBUG" = true ]; then
  CMD="${CMD} --debug"
elif [ "$UI" = true ]; then
  CMD="${CMD} --ui"
fi

if [ -n "$BROWSER" ]; then
  CMD="${CMD} --project=${BROWSER}"
fi

if [ -n "$SPEC" ]; then
  CMD="${CMD} ${SPEC}"
fi

print_info "Running tests..."
print_info "Command: ${CMD}"
echo ""

# Run tests
eval "${CMD}"

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
  print_info "✅ All tests passed!"
  echo ""
  print_info "View test report: npm run report"
else
  print_error "❌ Some tests failed (exit code: ${EXIT_CODE})"
  echo ""
  print_info "View test report: npm run report"
  print_info "View traces: npx playwright show-trace test-results/*/trace.zip"
fi

exit $EXIT_CODE

