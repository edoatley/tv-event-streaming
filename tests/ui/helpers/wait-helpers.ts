import { Page, Locator } from '@playwright/test';

/**
 * Wait for an element to be visible and stable
 */
export async function waitForElementStable(
  locator: Locator,
  timeout: number = 5000
): Promise<void> {
  await locator.waitFor({ state: 'visible', timeout });
  // Wait a bit more to ensure element is stable
  await locator.page().waitForTimeout(200);
}

/**
 * Wait for text content to change from initial value
 */
export async function waitForTextChange(
  locator: Locator,
  initialText: string,
  timeout: number = 30000
): Promise<string> {
  const startTime = Date.now();
  while (Date.now() - startTime < timeout) {
    const currentText = await locator.textContent();
    if (currentText && currentText !== initialText) {
      return currentText;
    }
    await locator.page().waitForTimeout(500);
  }
  throw new Error(`Text did not change from "${initialText}" within ${timeout}ms`);
}

/**
 * Wait for API call to complete by monitoring network activity
 */
export async function waitForApiCall(
  page: Page,
  urlPattern: string | RegExp,
  timeout: number = 10000
): Promise<void> {
  const responsePromise = page.waitForResponse(
    (response) => {
      const url = response.url();
      if (typeof urlPattern === 'string') {
        return url.includes(urlPattern);
      }
      return urlPattern.test(url);
    },
    { timeout }
  );
  await responsePromise;
}

/**
 * Wait for loading indicator to disappear
 */
export async function waitForLoadingToComplete(
  loadingLocator: Locator,
  timeout: number = 10000
): Promise<void> {
  try {
    // Wait for loading indicator to appear (if it does)
    await loadingLocator.waitFor({ state: 'visible', timeout: 1000 });
    // Then wait for it to disappear
    await loadingLocator.waitFor({ state: 'hidden', timeout });
  } catch {
    // If loading indicator never appears, that's fine
    // It might not be present if data loads quickly
  }
}

/**
 * Wait for alert dialog and get its message
 */
export async function waitForAlert(
  page: Page,
  timeout: number = 5000
): Promise<string> {
  return new Promise((resolve, reject) => {
    const timeoutId = setTimeout(() => {
      reject(new Error('Alert dialog did not appear within timeout'));
    }, timeout);

    page.once('dialog', (dialog) => {
      clearTimeout(timeoutId);
      const message = dialog.message();
      dialog.accept();
      resolve(message);
    });
  });
}

/**
 * Wait for navigation to complete
 */
export async function waitForNavigation(
  page: Page,
  urlPattern: string | RegExp,
  timeout: number = 10000
): Promise<void> {
  await page.waitForURL(urlPattern, { timeout });
}

