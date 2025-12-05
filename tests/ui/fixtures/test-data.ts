/**
 * Test data constants for UI tests
 */

// Load environment variables first to ensure they're available
import * as dotenv from 'dotenv';
import * as path from 'path';

// Load .env file with override to ensure values are set
dotenv.config({ path: path.resolve(__dirname, '../.env'), override: true });

export const TEST_USERS = {
  regular: {
    email: (process.env.TEST_USER_EMAIL || 'test.user@example.com').trim(),
    password: (process.env.TEST_USER_PASSWORD || '').trim(),
  },
  admin: {
    email: (process.env.ADMIN_USER_EMAIL || 'admin.user@example.com').trim(),
    password: (process.env.ADMIN_USER_PASSWORD || '').trim(),
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

