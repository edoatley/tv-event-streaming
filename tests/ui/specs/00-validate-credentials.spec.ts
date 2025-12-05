import { test, expect } from '../fixtures/test-context';
import { getIdToken } from '../helpers/cognito-helper';
import { TEST_USERS, COGNITO_CONFIG } from '../fixtures/test-data';

/**
 * This test runs first to validate that credentials are properly loaded
 * and can authenticate with Cognito before running other tests.
 * 
 * If this test fails, all other tests will likely fail with authentication errors.
 */
test.describe('Credential Validation', () => {
  test('should have valid test user credentials loaded from environment', async () => {
    // Verify credentials are loaded
    expect(TEST_USERS.regular.email).toBeTruthy();
    expect(TEST_USERS.regular.email).not.toBe('');
    expect(TEST_USERS.regular.password).toBeTruthy();
    expect(TEST_USERS.regular.password.length).toBeGreaterThan(0);
    
    // Verify password doesn't have whitespace issues
    expect(TEST_USERS.regular.password).toBe(TEST_USERS.regular.password.trim());
    expect(TEST_USERS.regular.email).toBe(TEST_USERS.regular.email.trim());
    
    // Verify Cognito config is loaded
    expect(COGNITO_CONFIG.testScriptClientId || COGNITO_CONFIG.clientId).toBeTruthy();
    
    console.log('✅ Test user credentials loaded:');
    console.log(`   Email: ${TEST_USERS.regular.email}`);
    console.log(`   Password length: ${TEST_USERS.regular.password.length}`);
    console.log(`   Client ID: ${COGNITO_CONFIG.testScriptClientId || COGNITO_CONFIG.clientId}`);
  });

  test('should authenticate test user with Cognito', async () => {
    const clientId = COGNITO_CONFIG.testScriptClientId || COGNITO_CONFIG.clientId;
    
    if (!clientId) {
      test.skip();
      return;
    }

    // Attempt authentication
    try {
      const token = await getIdToken(
        TEST_USERS.regular.email,
        TEST_USERS.regular.password
      );
      
      expect(token).toBeTruthy();
      expect(token.length).toBeGreaterThan(0);
      expect(token).toMatch(/^eyJ/); // JWT tokens start with "eyJ"
      
      console.log('✅ Test user authentication successful');
      console.log(`   Token length: ${token.length}`);
    } catch (error: any) {
      console.error('❌ Test user authentication failed:');
      console.error(`   Email: ${TEST_USERS.regular.email}`);
      console.error(`   Password length: ${TEST_USERS.regular.password.length}`);
      console.error(`   Client ID: ${clientId}`);
      console.error(`   Error: ${error.message}`);
      
      // Log environment variables for debugging
      console.error('   Environment check:');
      console.error(`   TEST_USER_EMAIL: ${process.env.TEST_USER_EMAIL ? 'SET' : 'NOT SET'}`);
      console.error(`   TEST_USER_PASSWORD: ${process.env.TEST_USER_PASSWORD ? `SET (length: ${process.env.TEST_USER_PASSWORD.length})` : 'NOT SET'}`);
      console.error(`   TEST_SCRIPT_USER_POOL_CLIENT_ID: ${process.env.TEST_SCRIPT_USER_POOL_CLIENT_ID ? 'SET' : 'NOT SET'}`);
      
      throw error;
    }
  });

  test('should have valid admin user credentials loaded from environment', async () => {
    expect(TEST_USERS.admin.email).toBeTruthy();
    expect(TEST_USERS.admin.email).not.toBe('');
    expect(TEST_USERS.admin.password).toBeTruthy();
    expect(TEST_USERS.admin.password.length).toBeGreaterThan(0);
    
    expect(TEST_USERS.admin.password).toBe(TEST_USERS.admin.password.trim());
    expect(TEST_USERS.admin.email).toBe(TEST_USERS.admin.email.trim());
    
    console.log('✅ Admin user credentials loaded:');
    console.log(`   Email: ${TEST_USERS.admin.email}`);
    console.log(`   Password length: ${TEST_USERS.admin.password.length}`);
  });

  test('should authenticate admin user with Cognito', async () => {
    const clientId = COGNITO_CONFIG.testScriptClientId || COGNITO_CONFIG.clientId;
    
    if (!clientId) {
      test.skip();
      return;
    }

    try {
      const token = await getIdToken(
        TEST_USERS.admin.email,
        TEST_USERS.admin.password
      );
      
      expect(token).toBeTruthy();
      expect(token.length).toBeGreaterThan(0);
      expect(token).toMatch(/^eyJ/);
      
      console.log('✅ Admin user authentication successful');
    } catch (error: any) {
      console.error('❌ Admin user authentication failed:');
      console.error(`   Email: ${TEST_USERS.admin.email}`);
      console.error(`   Password length: ${TEST_USERS.admin.password.length}`);
      console.error(`   Error: ${error.message}`);
      throw error;
    }
  });
});

