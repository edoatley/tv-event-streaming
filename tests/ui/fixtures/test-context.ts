import { test as base, Page } from '@playwright/test';
import { LoginPage } from '../pages/LoginPage';
import { MainViewPage } from '../pages/MainViewPage';
import { AdminViewPage } from '../pages/AdminViewPage';
import { TitleModalPage } from '../pages/TitleModalPage';

/**
 * Test context with all page objects
 */
export const test = base.extend<{
  loginPage: LoginPage;
  mainViewPage: MainViewPage;
  adminViewPage: AdminViewPage;
  titleModalPage: TitleModalPage;
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
});

export { expect } from '@playwright/test';

