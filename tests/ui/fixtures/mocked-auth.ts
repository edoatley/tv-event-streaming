import { test as base, Page } from '@playwright/test';
import { LoginPage } from '../pages/LoginPage';

/**
 * Creates a mocked JWT token for testing
 * This is a simplified version - in production, you'd want to use a proper JWT library
 */
function createMockedJWT(claims: Record<string, any>): string {
  // This is a basic mock - in reality, you'd need to properly sign the JWT
  // For testing purposes, we'll create a structure that the app might accept
  // Note: The actual app validates tokens with Cognito, so mocked tokens won't work
  // for real API calls, but can be useful for UI-only tests

  const header = {
    alg: 'HS256',
    typ: 'JWT',
  };

  const payload = {
    sub: claims.sub || 'mock-user-id',
    email: claims.email || 'test.user@example.com',
    'cognito:username': claims.username || 'testuser',
    'cognito:groups': claims.groups || [],
    exp: Math.floor(Date.now() / 1000) + 3600, // 1 hour from now
    iat: Math.floor(Date.now() / 1000),
    ...claims,
  };

  // In a real implementation, you'd properly encode and sign this
  // For now, we'll just store the payload as JSON in localStorage
  // The app will need to handle this gracefully
  return JSON.stringify(payload);
}

/**
 * Sets a mocked authentication token in the browser's localStorage
 */
export async function setMockedAuth(page: Page, userClaims: {
  email: string;
  sub?: string;
  username?: string;
  groups?: string[];
}): Promise<void> {
  const token = createMockedJWT({
    email: userClaims.email,
    sub: userClaims.sub || `mock-${userClaims.email}`,
    username: userClaims.username || userClaims.email.split('@')[0],
    groups: userClaims.groups || [],
  });

  await page.goto('/');
  await page.evaluate((token) => {
    localStorage.setItem('id_token', token);
  }, token);

  // Reload to apply the token
  await page.reload();
}

/**
 * Clears authentication from localStorage
 */
export async function clearMockedAuth(page: Page): Promise<void> {
  await page.evaluate(() => {
    localStorage.removeItem('id_token');
  });
}

/**
 * Fixture for tests that use mocked authentication
 */
export const testWithMockedAuth = base.extend<{ mockedAuthPage: Page }>({
  mockedAuthPage: async ({ page }, use) => {
    await setMockedAuth(page, {
      email: 'test.user@example.com',
      groups: [],
    });
    await use(page);
    await clearMockedAuth(page);
  },
});

