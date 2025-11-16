import { Page, Locator } from '@playwright/test';

export class MainViewPage {
  readonly page: Page;
  readonly titlesTab: Locator;
  readonly preferencesTab: Locator;
  readonly allTitlesTab: Locator;
  readonly recommendationsTab: Locator;
  readonly titlesContainer: Locator;
  readonly recommendationsContainer: Locator;
  readonly titlesLoading: Locator;
  readonly recommendationsLoading: Locator;
  readonly titleCards: Locator;
  readonly updatePreferencesBtn: Locator;
  readonly selectedSourcesList: Locator;
  readonly availableSourcesList: Locator;
  readonly selectedGenresList: Locator;
  readonly availableGenresList: Locator;

  constructor(page: Page) {
    this.page = page;
    this.titlesTab = page.locator('#main-nav-tabs a[data-page="titles"]');
    this.preferencesTab = page.locator('#main-nav-tabs a[data-page="preferences"]');
    this.allTitlesTab = page.locator('#titles-tab');
    this.recommendationsTab = page.locator('#recommendations-tab');
    this.titlesContainer = page.locator('#titlesContainer');
    this.recommendationsContainer = page.locator('#recommendationsContainer');
    this.titlesLoading = page.locator('#titlesLoading');
    this.recommendationsLoading = page.locator('#recommendationsLoading');
    this.titleCards = page.locator('.title-card');
    this.updatePreferencesBtn = page.locator('#updatePreferencesBtn');
    this.selectedSourcesList = page.locator('#selectedSourcesList');
    this.availableSourcesList = page.locator('#availableSourcesList');
    this.selectedGenresList = page.locator('#selectedGenresList');
    this.availableGenresList = page.locator('#availableGenresList');
  }

  async goto() {
    await this.page.goto('/#/main/titles');
  }

  async navigateToTitles() {
    await this.titlesTab.click();
    await this.page.waitForURL('**/#/main/titles');
  }

  async navigateToPreferences() {
    await this.preferencesTab.click();
    await this.page.waitForURL('**/#/main/preferences');
  }

  async switchToRecommendationsTab() {
    await this.recommendationsTab.click();
    await this.page.waitForSelector('#recommendations', { state: 'visible' });
  }

  async switchToAllTitlesTab() {
    await this.allTitlesTab.click();
    await this.page.waitForSelector('#titles', { state: 'visible' });
  }

  async getTitleCards() {
    return this.titleCards;
  }

  async getTitleCardCount(): Promise<number> {
    return await this.titleCards.count();
  }

  async clickTitleCard(index: number = 0) {
    const cards = await this.titleCards.all();
    if (cards.length > index) {
      await cards[index].click();
    } else {
      throw new Error(`Title card at index ${index} not found`);
    }
  }

  async waitForTitlesToLoad() {
    await this.titlesLoading.waitFor({ state: 'hidden' });
    // Wait a bit more for cards to render
    await this.page.waitForTimeout(500);
  }

  async waitForRecommendationsToLoad() {
    await this.recommendationsLoading.waitFor({ state: 'hidden' });
    // Wait a bit more for cards to render
    await this.page.waitForTimeout(500);
  }

  async isTitlesLoadingVisible(): Promise<boolean> {
    try {
      await this.titlesLoading.waitFor({ state: 'visible', timeout: 1000 });
      return true;
    } catch {
      return false;
    }
  }

  async getEmptyStateMessage(): Promise<string | null> {
    const emptyState = this.page.locator('text=No titles found');
    if (await emptyState.isVisible()) {
      return await emptyState.textContent();
    }
    return null;
  }

  async selectSource(sourceId: string) {
    const checkbox = this.page.locator(`input[name="source"][value="${sourceId}"]`);
    if (!(await checkbox.isChecked())) {
      await checkbox.check();
    }
  }

  async deselectSource(sourceId: string) {
    const checkbox = this.page.locator(`input[name="source"][value="${sourceId}"]`);
    if (await checkbox.isChecked()) {
      await checkbox.uncheck();
    }
  }

  async selectGenre(genreId: string) {
    const checkbox = this.page.locator(`input[name="genre"][value="${genreId}"]`);
    if (!(await checkbox.isChecked())) {
      await checkbox.check();
    }
  }

  async deselectGenre(genreId: string) {
    const checkbox = this.page.locator(`input[name="genre"][value="${genreId}"]`);
    if (await checkbox.isChecked()) {
      await checkbox.uncheck();
    }
  }

  async getSelectedSources(): Promise<string[]> {
    const checked = this.page.locator('input[name="source"]:checked');
    const count = await checked.count();
    const sources: string[] = [];
    for (let i = 0; i < count; i++) {
      const value = await checked.nth(i).getAttribute('value');
      if (value) sources.push(value);
    }
    return sources;
  }

  async getSelectedGenres(): Promise<string[]> {
    const checked = this.page.locator('input[name="genre"]:checked');
    const count = await checked.count();
    const genres: string[] = [];
    for (let i = 0; i < count; i++) {
      const value = await checked.nth(i).getAttribute('value');
      if (value) genres.push(value);
    }
    return genres;
  }

  async updatePreferences() {
    await this.updatePreferencesBtn.click();
    // Wait for alert or success message
    await this.page.waitForTimeout(1000);
  }

  async waitForPreferencesUpdate() {
    // Wait for the alert to appear and then dismiss it
    this.page.on('dialog', dialog => dialog.accept());
    await this.page.waitForTimeout(500);
  }
}

