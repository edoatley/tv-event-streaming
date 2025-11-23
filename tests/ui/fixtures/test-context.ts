import { test as base, Page } from '@playwright/test';
import { LoginPage } from '../pages/LoginPage';
import { MainViewPage } from '../pages/MainViewPage';
import { AdminViewPage } from '../pages/AdminViewPage';
import { TitleModalPage } from '../pages/TitleModalPage';
import { authenticateUserInBrowser } from './auth';
import { TEST_USERS } from './test-data';

/**
 * Test context with all page objects and authentication fixtures
 */
export const test = base.extend<{
  loginPage: LoginPage;
  mainViewPage: MainViewPage;
  adminViewPage: AdminViewPage;
  titleModalPage: TitleModalPage;
  authenticatedPage: Page;
  adminPage: Page;
}>({
  loginPage: async ({ page }, use) => {
    await use(new LoginPage(page));
  },
  mainViewPage: async ({ page }, use) => {
    await use(new MainViewPage(page));
  },
  adminViewPage: async ({ page }, use) => {
    await use(new AdminViewPage(page));
  },
  titleModalPage: async ({ page }, use) => {
    await use(new TitleModalPage(page));
  },
  authenticatedPage: async ({ page }, use) => {
    const email = TEST_USERS.regular.email;
    const password = TEST_USERS.regular.password;

    if (!password) {
      throw new Error('TEST_USER_PASSWORD environment variable is required for authenticated tests');
    }

    await authenticateUserInBrowser(page, email, password);
    await use(page);
  },
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

export { expect } from '@playwright/test';

