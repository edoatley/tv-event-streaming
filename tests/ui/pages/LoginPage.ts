import { Page, Locator } from '@playwright/test';

export class LoginPage {
  readonly page: Page;
  readonly loginButton: Locator;
  readonly logoutButton: Locator;
  readonly userGreeting: Locator;
  readonly adminNav: Locator;
  readonly loginActionBtn: Locator;
  readonly signInCard: Locator;

  constructor(page: Page) {
    this.page = page;
    this.loginButton = page.locator('#loginBtn');
    this.logoutButton = page.locator('#logoutBtn');
    this.userGreeting = page.locator('#user-greeting');
    this.adminNav = page.locator('#adminNav');
    this.loginActionBtn = page.locator('#loginActionBtn');
    this.signInCard = page.locator('.card:has-text("Sign In Required")');
  }

  async goto() {
    await this.page.goto('/');
  }

  async waitForLoginPage() {
    await this.signInCard.waitFor({ state: 'visible' });
  }

  async clickLoginButton() {
    await this.loginButton.click();
  }

  async clickLoginActionButton() {
    await this.loginActionBtn.click();
  }

  async clickLogoutButton() {
    await this.logoutButton.click();
  }

  async isLoggedIn(): Promise<boolean> {
    try {
      await this.logoutButton.waitFor({ state: 'visible', timeout: 2000 });
      return true;
    } catch {
      return false;
    }
  }

  async isLoginButtonVisible(): Promise<boolean> {
    try {
      await this.loginButton.waitFor({ state: 'visible', timeout: 2000 });
      return true;
    } catch {
      return false;
    }
  }

  async getUserEmail(): Promise<string | null> {
    const greeting = await this.userGreeting.textContent();
    // Extract email from "Welcome, email@example.com"
    const match = greeting?.match(/Welcome, (.+)/);
    return match ? match[1].trim() : null;
  }

  async isAdminNavVisible(): Promise<boolean> {
    try {
      await this.adminNav.waitFor({ state: 'visible', timeout: 2000 });
      return true;
    } catch {
      return false;
    }
  }
}

