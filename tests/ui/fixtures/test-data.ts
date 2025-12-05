/**
 * Test data constants for UI tests
 */

// Load environment variables first to ensure they're available
import * as dotenv from 'dotenv';
import * as path from 'path';
import * as fs from 'fs';

// Determine the correct .env file path
const envPath = path.resolve(__dirname, '../.env');

// Load .env file with override to ensure values are set
const dotenvResult = dotenv.config({ path: envPath, override: true });

// Log if .env file was found (only in debug mode to avoid noise)
if (process.env.DEBUG_ENV_LOADING === 'true') {
  if (dotenvResult.error) {
    console.warn(`⚠️  Warning: Could not load .env file: ${dotenvResult.error.message}`);
  } else {
    console.log(`✅ Loaded .env file from: ${envPath}`);
  }
  
  // Verify file exists
  if (!fs.existsSync(envPath)) {
    console.warn(`⚠️  Warning: .env file does not exist at: ${envPath}`);
  }
}

// Helper function to safely get and trim environment variables
function getEnvVar(key: string, defaultValue: string = ''): string {
  const value = process.env[key] || defaultValue;
  return value.trim();
}

export const TEST_USERS = {
  regular: {
    email: getEnvVar('TEST_USER_EMAIL', 'test.user@example.com'),
    password: getEnvVar('TEST_USER_PASSWORD', ''),
  },
  admin: {
    email: getEnvVar('ADMIN_USER_EMAIL', 'admin.user@example.com'),
    password: getEnvVar('ADMIN_USER_PASSWORD', ''),
  },
};

export const COGNITO_CONFIG = {
  userPoolId: process.env.COGNITO_USER_POOL_ID || '',
  clientId: process.env.COGNITO_CLIENT_ID || '',
  testScriptClientId: process.env.TEST_SCRIPT_USER_POOL_CLIENT_ID || '',
  region: process.env.AWS_REGION || 'eu-west-2',
  profile: process.env.AWS_PROFILE || 'streaming',
};

export const EXPECTED_TEXT = {
  loginPage: {
    title: 'Sign In Required',
    message: 'Please log in to access the UK TV Guide.',
    signInButton: 'Sign In',
  },
  mainView: {
    titlesTab: 'Titles',
    preferencesTab: 'Preferences',
    allTitles: 'All Titles',
    recommendations: 'Recommendations',
    noTitlesFound: 'No titles found.',
  },
  adminPanel: {
    title: 'Administrator Panel',
    dataManagement: 'Data Management',
    systemStatus: 'System Status',
  },
};

export const TIMEOUTS = {
  short: 2000,
  medium: 5000,
  long: 10000,
  veryLong: 30000,
  pageLoad: 30000,
  apiCall: 10000,
};

