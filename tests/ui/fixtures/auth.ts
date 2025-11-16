import { test as base, Page, BrowserContext } from '@playwright/test';
import { getIdToken } from '../helpers/cognito-helper';
import { TEST_USERS, COGNITO_CONFIG } from './test-data';

/**
 * Authenticates a user programmatically and sets the token in the browser context
 */
export async function authenticateUserInBrowser(
  page: Page,
  email: string,
  password: string
): Promise<string> {
  // Get the ID token using Cognito
  const idToken = await getIdToken(email, password);

  // Set the token in localStorage
  await page.goto('/');
  await page.evaluate((token) => {
    localStorage.setItem('id_token', token);
  }, idToken);

  // Reload the page to apply authentication
  await page.reload();

  return idToken;
}

/**
 * Creates authenticated context with storage state
 */
export async function createAuthenticatedContext(
  context: BrowserContext,
  email: string,
  password: string
): Promise<BrowserContext> {
  // Create a new page to authenticate
  const page = await context.newPage();
  
  // Authenticate and get token
  const idToken = await getIdToken(email, password);

  // Set token in localStorage
  await page.goto('/');
  await page.evaluate((token) => {
    localStorage.setItem('id_token', token);
  }, idToken);

  // Save storage state for reuse
  await context.storageState({ path: `playwright/.auth/${email.replace('@', '_at_')}.json` });

  await page.close();
  return context;
}

/**
 * Fixture for authenticated regular user
 */
export const authenticatedUser = base.extend<{ authenticatedPage: Page }>({
  authenticatedPage: async ({ page }, use) => {
    const email = TEST_USERS.regular.email;
    const password = TEST_USERS.regular.password;

    if (!password) {
      throw new Error('TEST_USER_PASSWORD environment variable is required for authenticated tests');
    }

    await authenticateUserInBrowser(page, email, password);
    await use(page);
  },
});

/**
 * Fixture for authenticated admin user
 */
export const authenticatedAdmin = base.extend<{ adminPage: Page }>({
  adminPage: async ({ page }, use) => {
    const email = TEST_USERS.admin.email;
    const password = TEST_USERS.admin.password;

    if (!password) {
      throw new Error('ADMIN_USER_PASSWORD environment variable is required for admin tests');
    }

    await authenticateUserInBrowser(page, email, password);
    await use(page);
  },
});

/**
 * Fixture that provides both authenticated contexts
 */
export const testWithAuth = base.extend<{
  userPage: Page;
  adminPage: Page;
}>({
  userPage: async ({ browser }, use) => {
    const context = await browser.newContext();
    const page = await context.newPage();
    
    const email = TEST_USERS.regular.email;
    const password = TEST_USERS.regular.password;

    if (!password) {
      throw new Error('TEST_USER_PASSWORD environment variable is required');
    }

    await authenticateUserInBrowser(page, email, password);
    await use(page);
    await context.close();
  },
  adminPage: async ({ browser }, use) => {
    const context = await browser.newContext();
    const page = await context.newPage();
    
    const email = TEST_USERS.admin.email;
    const password = TEST_USERS.admin.password;

    if (!password) {
      throw new Error('ADMIN_USER_PASSWORD environment variable is required');
    }

    await authenticateUserInBrowser(page, email, password);
    await use(page);
    await context.close();
  },
});

