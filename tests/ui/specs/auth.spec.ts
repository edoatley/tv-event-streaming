import { test, expect } from '../fixtures/test-context';
import { authenticatedUser } from '../fixtures/auth';
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

    test('should allow user to log out', async ({ authenticatedPage, loginPage }) => {
      await authenticatedPage.goto('/');
      
      // Should be logged in
      await expect(loginPage.logoutButton).toBeVisible();
      
      // Click logout
      await loginPage.clickLogoutButton();
      
      // Should redirect to login page
      await authenticatedPage.waitForURL('**/#/**', { timeout: 10000 });
      
      // Should show login button
      await expect(loginPage.loginButton).toBeVisible();
      await expect(loginPage.logoutButton).not.toBeVisible();
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

