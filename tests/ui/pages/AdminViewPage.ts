import { Page, Locator } from '@playwright/test';

export class AdminViewPage {
  readonly page: Page;
  readonly refreshReferenceDataBtn: Locator;
  readonly refreshTitleDataBtn: Locator;
  readonly triggerEnrichmentBtn: Locator;
  readonly generateSummaryBtn: Locator;
  readonly refreshReferenceDataStatus: Locator;
  readonly refreshTitleDataStatus: Locator;
  readonly triggerEnrichmentStatus: Locator;
  readonly dynamoDbSummaryOutput: Locator;

  constructor(page: Page) {
    this.page = page;
    this.refreshReferenceDataBtn = page.locator('#refreshReferenceDataBtn');
    this.refreshTitleDataBtn = page.locator('#refreshTitleDataBtn');
    this.triggerEnrichmentBtn = page.locator('#triggerEnrichmentBtn');
    this.generateSummaryBtn = page.locator('#generateSummaryBtn');
    this.refreshReferenceDataStatus = page.locator('#refreshReferenceDataStatus');
    this.refreshTitleDataStatus = page.locator('#refreshTitleDataStatus');
    this.triggerEnrichmentStatus = page.locator('#triggerEnrichmentStatus');
    this.dynamoDbSummaryOutput = page.locator('#dynamoDbSummaryOutput');
  }

  async goto() {
    await this.page.goto('/#/admin');
  }

  async refreshReferenceData() {
    await this.refreshReferenceDataBtn.click();
  }

  async refreshTitleData() {
    await this.refreshTitleDataBtn.click();
  }

  async triggerEnrichment() {
    await this.triggerEnrichmentBtn.click();
  }

  async getDynamoDbSummary() {
    await this.generateSummaryBtn.click();
  }

  async waitForStatusMessage(statusElement: Locator, timeout: number = 30000) {
    // Wait for status to change from "Refreshing..." or "Triggering..." or "Generating..."
    await statusElement.waitFor({ state: 'visible' });
    const initialText = await statusElement.textContent();
    
    // Wait for the text to change (indicating completion)
    await this.page.waitForFunction(
      (element, initial) => {
        return element.textContent !== initial && 
               !element.textContent?.includes('Refreshing') &&
               !element.textContent?.includes('Triggering') &&
               !element.textContent?.includes('Generating');
      },
      await statusElement.elementHandle(),
      initialText,
      { timeout }
    );
  }

  async getReferenceDataStatus(): Promise<string> {
    return await this.refreshReferenceDataStatus.textContent() || '';
  }

  async getTitleDataStatus(): Promise<string> {
    return await this.refreshTitleDataStatus.textContent() || '';
  }

  async getEnrichmentStatus(): Promise<string> {
    return await this.triggerEnrichmentStatus.textContent() || '';
  }

  async getDynamoDbSummaryText(): Promise<string> {
    await this.dynamoDbSummaryOutput.waitFor({ state: 'visible' });
    return await this.dynamoDbSummaryOutput.textContent() || '';
  }

  async isAdminPanelVisible(): Promise<boolean> {
    try {
      await this.page.waitForSelector('.admin-panel', { state: 'visible', timeout: 2000 });
      return true;
    } catch {
      return false;
    }
  }
}

