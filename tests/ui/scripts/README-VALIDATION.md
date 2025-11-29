# Password Validation Scripts

## Overview

These scripts validate that passwords retrieved from Secrets Manager are correct by testing authentication with Cognito before running UI tests.

## Scripts

### `fetch-stack-outputs.sh`
Fetches CloudFormation stack outputs and retrieves passwords from Secrets Manager, updating the `.env` file.

**Usage:**
```bash
./scripts/fetch-stack-outputs.sh [stack-name] [region] [profile]
```

### `validate-passwords.sh`
Validates passwords by attempting to authenticate with Cognito using AWS CLI.

**Usage:**
```bash
./scripts/validate-passwords.sh [env-file] [region] [profile]
```

### `test-password-validation.sh`
End-to-end test script that runs both fetch and validation.

**Usage:**
```bash
./scripts/test-password-validation.sh [stack-name] [region] [profile]
```

## Testing Locally

1. **Fetch stack outputs and passwords:**
   ```bash
   cd tests/ui
   ./scripts/fetch-stack-outputs.sh tv-event-streaming-gha eu-west-2 streaming
   ```

2. **Validate passwords:**
   ```bash
   ./scripts/validate-passwords.sh .env eu-west-2 streaming
   ```

3. **Or run the full test:**
   ```bash
   ./scripts/test-password-validation.sh tv-event-streaming-gha eu-west-2 streaming
   ```

## What the Validation Does

1. Reads Cognito configuration from `.env` file
2. Attempts authentication for both test and admin users
3. Fails with clear error messages if authentication fails
4. Only succeeds if both users can authenticate

## Error Messages

The validation script provides detailed error messages including:
- Which user failed
- Client ID used
- Password length
- AWS error details
- Suggestions for fixing the issue

This helps identify whether the problem is:
- Incorrect password in Secrets Manager
- Password not set correctly in Cognito
- User account not confirmed
- Cognito client configuration issue
