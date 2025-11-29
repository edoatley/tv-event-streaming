import { test, expect } from '../fixtures/test-context';
import { TEST_USERS, EXPECTED_TEXT } from '../fixtures/test-data';

test.describe('Authentication', () => {
  test.describe('Unauthenticated user', () => {
    test('should show login page when not authenticated', async ({ page, loginPage }) => {
      await page.goto('/');
      await loginPage.waitForLoginPage();

      const signInCard = page.locator('.card:has-text("Sign In Required")');
      await expect(signInCard).toBeVisible();
      await expect(signInCard).toContainText(EXPECTED_TEXT.loginPage.title);
      await expect(signInCard).toContainText(EXPECTED_TEXT.loginPage.message);
    });

    test('should show login button when not authenticated', async ({ page, loginPage }) => {
      await page.goto('/');
      await expect(loginPage.loginButton).toBeVisible();
      await expect(loginPage.logoutButton).not.toBeVisible();
    });

    test('should redirect to login when accessing protected route', async ({ page }) => {
      await page.goto('/#/main/titles');
      // Should redirect to login
      await page.waitForURL('**/#/**', { timeout: 5000 });
      // Check that we're on a login-required page
      const signInCard = page.locator('.card:has-text("Sign In Required")');
      await expect(signInCard).toBeVisible();
    });
  });

  test.describe('Authenticated user', () => {
    test('should authenticate user and show main view', async ({ authenticatedPage, loginPage, mainViewPage }) => {
      // User should be authenticated via fixture
      await authenticatedPage.goto('/');

      // Should be redirected to main view
      await authenticatedPage.waitForURL('**/#/main/titles', { timeout: 5000 });

      // Should show logout button
      await expect(loginPage.logoutButton).toBeVisible();
      await expect(loginPage.loginButton).not.toBeVisible();

      // Should show user greeting
      await expect(loginPage.userGreeting).toBeVisible();
      const email = await loginPage.getUserEmail();
      expect(email).toBe(TEST_USERS.regular.email);
    });

    test('should display user email in greeting', async ({ authenticatedPage, loginPage }) => {
      await authenticatedPage.goto('/');
      await expect(loginPage.userGreeting).toBeVisible();
      
      const greetingText = await loginPage.userGreeting.textContent();
      expect(greetingText).toContain(TEST_USERS.regular.email);
    });

    test('should allow user to log out', async ({ authenticatedPage, loginPage, page }) => {
      await authenticatedPage.goto('/');
      
      // Should be logged in
      await expect(loginPage.logoutButton).toBeVisible();
      
      // Get the current hostname before logout
      const currentHostname = new URL(page.url()).hostname;
      
      // Click logout - this will redirect to Cognito logout URL and back
      await loginPage.clickLogoutButton();
      
      // Wait for redirect back to the app (Cognito will redirect)
      // Wait for URL to return to our app's domain (not Cognito)
      try {
        await page.waitForURL((url) => {
          // Wait for URL to be back on our app's domain
          // Use proper hostname comparison instead of substring matching to prevent subdomain attacks
          const hostname = url.hostname.toLowerCase();
          const cognitoDomains = ['amazoncognito.com', 'cognito-idp.us-east-1.amazonaws.com', 'cognito-idp.us-west-2.amazonaws.com'];
          const isCognitoDomain = cognitoDomains.some(domain => 
            hostname === domain || hostname.endsWith('.' + domain)
          );
          return url.hostname === currentHostname || !isCognitoDomain;
        }, { timeout: 30000, waitUntil: 'domcontentloaded' });
      } catch (e) {
        // If URL wait times out, try waiting for load state as fallback
        await page.waitForLoadState('domcontentloaded', { timeout: 10000 }).catch(() => null);
      }
      
      // Wait for page to stabilize after redirect
      await page.waitForTimeout(2000);
      
      // After logout, check if we're logged out by checking localStorage
      const token = await page.evaluate(() => localStorage.getItem('id_token'));
      expect(token).toBeNull();
      
      // Should show login button or login page
      const loginButtonVisible = await loginPage.isLoginButtonVisible().catch(() => false);
      const signInCard = page.locator('.card:has-text("Sign In Required")');
      const hasSignInCard = await signInCard.isVisible().catch(() => false);
      
      // After logout, either login button should be visible or we're on login page
      expect(loginButtonVisible || hasSignInCard).toBeTruthy();
    });

    test('should not show admin link for regular user', async ({ authenticatedPage, loginPage }) => {
      await authenticatedPage.goto('/');
      
      // Regular user should not see admin link
      await expect(loginPage.adminNav).not.toBeVisible();
    });
  });

  test.describe('Token persistence', () => {
    test('should persist authentication across page refresh', async ({ authenticatedPage, loginPage }) => {
      await authenticatedPage.goto('/');
      
      // Should be authenticated
      await expect(loginPage.logoutButton).toBeVisible();
      
      // Refresh page
      await authenticatedPage.reload();
      
      // Should still be authenticated
      await expect(loginPage.logoutButton).toBeVisible();
      await expect(loginPage.loginButton).not.toBeVisible();
    });
  });
});

