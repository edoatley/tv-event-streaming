# UI Test Suite

Automated UI test suite for the TV Event Streaming application using Playwright.

## Prerequisites

- **Node.js** (v18 or higher)
- **npm** or **yarn**
- **AWS CLI** configured with appropriate credentials
- **AWS Profile** set up (default: `streaming`)
- Access to the deployed application
- Test user credentials (test.user@example.com and admin.user@example.com)

## Setup

1. **Install dependencies:**
   ```bash
   cd tests/ui
   npm install
   ```

2. **Install Playwright browsers:**
   ```bash
   npx playwright install
   ```

3. **Configure environment variables:**
   
   **Option 1: Use build-env.sh (Recommended)**
   ```bash
   ./scripts/build-env.sh <stack-name> [region] [profile]
   ```
   
   This script automatically:
   - Copies `env.example` to `.env` if it doesn't exist
   - Sources values from the root project `.env` file (if it exists at the project root)
   - Fetches CloudFormation stack outputs and populates `.env`
   - Checks for missing required variables
   
   **Option 2: Manual setup**
   ```bash
   cp env.example .env
   # Edit .env and set required values
   # Or use fetch-stack-outputs.sh to get values from CloudFormation:
   ./scripts/fetch-stack-outputs.sh <stack-name> <region>
   ```
   
   Required variables:
   - `BASE_URL` - The URL of your deployed application
   - `COGNITO_USER_POOL_ID` - Cognito User Pool ID
   - `COGNITO_CLIENT_ID` - Cognito App Client ID
   - `TEST_SCRIPT_USER_POOL_CLIENT_ID` - Test Script Client ID (allows USER_PASSWORD_AUTH)
   - `TEST_USER_EMAIL` - Test user email
   - `TEST_USER_PASSWORD` - Test user password
   - `ADMIN_USER_EMAIL` - Admin user email
   - `ADMIN_USER_PASSWORD` - Admin user password
   - `AWS_REGION` - AWS region (default: eu-west-2)
   - `AWS_PROFILE` - AWS profile name (default: streaming)

## Running Tests

### Run all tests
```bash
npm test
```

### Run tests in headed mode (see browser)
```bash
npm run test:headed
```

### Run tests in UI mode (interactive)
```bash
npm run test:ui
```

### Run tests in debug mode
```bash
npm run test:debug
```

### Run specific test file
```bash
npm run test:auth          # Authentication tests
npm run test:preferences    # Preferences tests
npm run test:titles         # Titles view tests
npm run test:admin          # Admin panel tests
```

### Run tests for specific browser
```bash
npm run test:chrome         # Chrome only
npm run test:firefox        # Firefox only
```

### Run specific test
```bash
npx playwright test specs/auth.spec.ts -g "should authenticate user"
```

### Run tests using the shell script
```bash
./run-tests.sh
```

## Test Structure

```
tests/ui/
├── specs/              # Test specifications
│   ├── auth.spec.ts           # Authentication tests
│   ├── preferences.spec.ts    # User preferences tests
│   ├── titles.spec.ts          # Titles view tests
│   └── admin.spec.ts           # Admin panel tests
├── pages/              # Page Object Models
│   ├── LoginPage.ts
│   ├── MainViewPage.ts
│   ├── AdminViewPage.ts
│   └── TitleModalPage.ts
├── fixtures/           # Test fixtures and helpers
│   ├── auth.ts                 # Authentication fixtures
│   ├── mocked-auth.ts          # Mocked authentication
│   ├── test-data.ts            # Test data constants
│   └── test-context.ts         # Test context with page objects
└── helpers/            # Helper utilities
    ├── api-helper.ts           # API interaction helpers
    ├── cognito-helper.ts       # Cognito authentication
    └── wait-helpers.ts         # Custom wait conditions
```

## Test Categories

### Smoke Tests
Critical path tests that verify basic functionality:
- User authentication
- Basic navigation
- Page loading

### Functional Tests
Tests that verify all user-facing features:
- Preferences management
- Title browsing
- Admin panel operations

### Integration Tests
Tests that verify cross-feature workflows:
- Preferences → Titles display
- Authentication → Access control

## Debugging Tests

### View test report
After running tests, view the HTML report:
```bash
npm run report
```

### Debug a failing test
1. Run the test in debug mode:
   ```bash
   npx playwright test specs/auth.spec.ts --debug
   ```

2. Use the Playwright Inspector to step through the test

### View trace
Tests automatically capture traces on failure. View them:
```bash
npx playwright show-trace test-results/<test-name>/trace.zip
```

### Screenshots and videos
- Screenshots are captured on test failure
- Videos are recorded for failed tests
- Both are saved in `test-results/` directory

### Console logs
Playwright captures browser console logs. Check test output for console messages.

## Authentication

The test suite supports two authentication approaches:

### 1. Programmatic Authentication (Primary)
Uses AWS SDK to authenticate with Cognito programmatically. This provides realistic end-to-end testing.

**Requirements:**
- `TEST_SCRIPT_USER_POOL_CLIENT_ID` must be set (this client allows USER_PASSWORD_AUTH)
- AWS credentials configured
- Test user passwords set in Cognito

**Usage:**
```typescript
import { authenticatedUser } from '../fixtures/auth';

test('my test', async ({ authenticatedPage }) => {
  // User is automatically authenticated
  await authenticatedPage.goto('/');
});
```

### 2. Mocked Authentication (Secondary)
Uses mocked tokens for faster, isolated component testing. Note: Mocked tokens won't work for real API calls.

**Usage:**
```typescript
import { testWithMockedAuth } from '../fixtures/mocked-auth';

testWithMockedAuth('my test', async ({ mockedAuthPage }) => {
  // User has mocked authentication
  await mockedAuthPage.goto('/');
});
```

## Test Data Management

### Setting up test data
Before running tests, ensure:
1. Test users exist in Cognito (test.user@example.com, admin.user@example.com)
2. User passwords are set
3. Admin user is in SecurityAdmins group
4. Reference data (sources, genres) exists in DynamoDB
5. Title data exists (may need to trigger ingestion)

### Test data scripts
```bash
./scripts/setup-test-data.sh    # Set up test data
./scripts/ensure-test-data.sh   # Ensure test data exists (idempotent)
./scripts/cleanup-test-data.sh   # Clean up test data
```

## Troubleshooting

### Tests fail with authentication errors
- Verify `TEST_SCRIPT_USER_POOL_CLIENT_ID` is set correctly
- Check that test user passwords are set in Cognito
- Verify AWS credentials are configured
- Check that the Cognito client allows USER_PASSWORD_AUTH flow

### Tests fail with "BASE_URL not set"
- Set `BASE_URL` in `.env` file
- Or use `build-env.sh` or `fetch-stack-outputs.sh` to get it from CloudFormation

### Tests timeout
- Check network connectivity to the application
- Verify the application is deployed and accessible
- Increase timeout values in `playwright.config.ts` if needed

### Tests fail with "Element not found"
- Application may have changed - update selectors in Page Objects
- Check that the application is fully loaded before interacting
- Use `waitFor` methods to ensure elements are ready

### Browser not found
- Run `npx playwright install` to install browsers
- Or install specific browser: `npx playwright install chromium`

## Adding New Tests

1. **Create a new test file** in `specs/` directory:
   ```typescript
   import { test, expect } from '../fixtures/test-context';
   
   test.describe('My Feature', () => {
     test('should do something', async ({ page, mainViewPage }) => {
       // Test implementation
     });
   });
   ```

2. **Add page methods** if needed in the appropriate Page Object

3. **Add test data** to `fixtures/test-data.ts` if needed

4. **Run the test** to verify it works

## Configuration

### Playwright Configuration
Edit `playwright.config.ts` to:
- Change timeouts
- Add/remove browsers
- Configure retries
- Change reporter settings

### Test Timeouts
Default timeouts are defined in `fixtures/test-data.ts`. Adjust as needed for your environment.

## CI/CD Integration

The test suite is designed to be integrated into CI/CD pipelines. See the plan document for future CI/CD integration steps.

For now, tests can be run locally after deployment to validate the application.

## Best Practices

1. **Use Page Objects** - Keep selectors and interactions in Page Objects
2. **Use Fixtures** - Leverage authentication fixtures for consistent setup
3. **Wait for Elements** - Always wait for elements before interacting
4. **Handle Async Operations** - Use proper waits for API calls and loading states
5. **Keep Tests Independent** - Each test should be able to run in isolation
6. **Use Descriptive Names** - Test names should clearly describe what they test
7. **Clean Up** - Tests should clean up after themselves when possible

## Support

For issues or questions:
1. Check the troubleshooting section
2. Review test output and screenshots
3. Check Playwright documentation: https://playwright.dev
4. Review the main project README for application-specific details

