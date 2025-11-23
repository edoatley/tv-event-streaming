import { Page, Locator } from '@playwright/test';

export class TitleModalPage {
  readonly page: Page;
  readonly modal: Locator;
  readonly modalTitle: Locator;
  readonly modalImage: Locator;
  readonly modalPlot: Locator;
  readonly modalRating: Locator;
  readonly modalSources: Locator;
  readonly modalGenres: Locator;
  readonly closeButton: Locator;

  constructor(page: Page) {
    this.page = page;
    this.modal = page.locator('#titleModal');
    this.modalTitle = page.locator('#titleModalTitle');
    this.modalImage = page.locator('#titleModalImage');
    this.modalPlot = page.locator('#titleModalPlot');
    this.modalRating = page.locator('#titleModalRating');
    this.modalSources = page.locator('#titleModalSources');
    this.modalGenres = page.locator('#titleModalGenres');
    this.closeButton = page.locator('#titleModal .btn-close');
  }

  async waitForModal() {
    await this.modal.waitFor({ state: 'visible' });
  }

  async getTitle(): Promise<string> {
    return await this.modalTitle.textContent() || '';
  }

  async getPlot(): Promise<string> {
    return await this.modalPlot.textContent() || '';
  }

  async getRating(): Promise<string> {
    return await this.modalRating.textContent() || '';
  }

  async getSources(): Promise<string> {
    return await this.modalSources.textContent() || '';
  }

  async getGenres(): Promise<string> {
    return await this.modalGenres.textContent() || '';
  }

  async getImageSrc(): Promise<string | null> {
    return await this.modalImage.getAttribute('src');
  }

  async close() {
    await this.closeButton.click();
    await this.modal.waitFor({ state: 'hidden' });
  }

  async isVisible(): Promise<boolean> {
    try {
      await this.modal.waitFor({ state: 'visible', timeout: 2000 });
      return true;
    } catch {
      return false;
    }
  }
}

