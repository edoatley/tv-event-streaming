import { defineConfig, devices } from '@playwright/test';
import * as dotenv from 'dotenv';
import * as path from 'path';
import * as fs from 'fs';

// Load environment variables from .env file
// Use override: true to ensure values from .env file override any existing env vars
const envPath = path.resolve(__dirname, '.env');
const dotenvResult = dotenv.config({ path: envPath, override: true });

// Verify .env file was loaded (only log if there's an error or in debug mode)
if (dotenvResult.error) {
  console.warn(`⚠️  Warning: Could not load .env file: ${dotenvResult.error.message}`);
  console.warn(`   Expected path: ${envPath}`);
  if (!fs.existsSync(envPath)) {
    console.warn(`   File does not exist at this path`);
  }
} else if (process.env.DEBUG_ENV_LOADING === 'true') {
  console.log(`✅ Loaded .env file from: ${envPath}`);
}

/**
 * See https://playwright.dev/docs/test-configuration.
 */
export default defineConfig({
  testDir: './specs',
  
  /* Run tests in files in parallel */
  fullyParallel: true,
  
  /* Fail the build on CI if you accidentally left test.only in the source code. */
  forbidOnly: !!process.env.CI,
  
  /* Retry on CI only */
  retries: process.env.CI ? 2 : 0,
  
  /* Opt out of parallel tests on CI. */
  workers: process.env.CI ? 1 : undefined,
  
  /* Reporter to use. See https://playwright.dev/docs/test-reporters */
  // HTML reports are always generated, but server only opens if PLAYWRIGHT_HTML_REPORT=true
  // View reports manually with: npx playwright show-report
  reporter: [
    ['html', { 
      open: process.env.PLAYWRIGHT_HTML_REPORT === 'true' ? 'always' : 'never' 
    }],
    ['list']
  ],
  
  /* Shared settings for all the projects below. See https://playwright.dev/docs/api/class-testoptions. */
  use: {
    /* Base URL to use in actions like `await page.goto('/')`. */
    baseURL: process.env.BASE_URL || 'http://localhost:3000',
    
    /* Collect trace when retrying the failed test. See https://playwright.dev/docs/trace-viewer */
    trace: 'on-first-retry',
    
    /* Screenshot on failure */
    screenshot: 'only-on-failure',
    
    /* Video on failure */
    video: 'retain-on-failure',
    
    /* Navigation timeout */
    navigationTimeout: 30000,
    
    /* Action timeout */
    actionTimeout: 15000,
  },

  /* Configure projects for major browsers */
  projects: [
    {
      name: 'chromium',
      use: { 
        ...devices['Desktop Chrome'],
        // Run headless by default unless --headed flag is used
        headless: true,
      },
    },
    // Firefox project - only run if not in CI or if explicitly requested
    ...(process.env.CI && !process.env.RUN_FIREFOX_TESTS ? [] : [{
      name: 'firefox',
      use: { 
        ...devices['Desktop Firefox'],
        // Run headless by default unless --headed flag is used
        headless: true,
      },
    }]),
  ],

  /* Run your local dev server before starting the tests */
  // webServer: {
  //   command: 'npm run start',
  //   url: 'http://127.0.0.1:3000',
  //   reuseExistingServer: !process.env.CI,
  // },
});

