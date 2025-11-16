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
    // Click the preferences tab
    await this.preferencesTab.click();
    
    // Wait for URL to change
    await this.page.waitForURL('**/#/main/preferences', { timeout: 10000 });
    
    // Wait for the router to handle the navigation and render the preferences page
    // The preferences page should have the updatePreferencesBtn
    await this.page.waitForSelector('#updatePreferencesBtn', { state: 'attached', timeout: 20000 }).catch(async () => {
      // If button doesn't appear, wait a bit more and check URL again
      await this.page.waitForTimeout(2000);
      const currentUrl = this.page.url();
      if (!currentUrl.includes('#/main/preferences')) {
        // URL didn't change, try clicking again
        await this.preferencesTab.click();
        await this.page.waitForURL('**/#/main/preferences', { timeout: 10000 });
        await this.page.waitForTimeout(1000);
      }
      // Try one more time
      await this.page.waitForSelector('#updatePreferencesBtn', { state: 'attached', timeout: 10000 });
    });
    
    // Wait for preferences data to load from API - wait for lists to have content
    // The lists should be populated (either with checkboxes or empty state messages)
    await this.page.waitForFunction(
      () => {
        const selectedSources = document.getElementById('selectedSourcesList');
        const selectedGenres = document.getElementById('selectedGenresList');
        const availableSources = document.getElementById('availableSourcesList');
        const availableGenres = document.getElementById('availableGenresList');
        // Check if all lists exist and have some content (even if just empty state message)
        return selectedSources && selectedGenres && availableSources && availableGenres &&
               (selectedSources.textContent?.trim() || availableSources.textContent?.trim() ||
                selectedGenres.textContent?.trim() || availableGenres.textContent?.trim());
      },
      { timeout: 20000 }
    ).catch(() => {
      // If function times out, continue anyway - lists might be empty
    });
    // Give a bit more time for UI to stabilize
    await this.page.waitForTimeout(1000);
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
    // Look specifically in the titles container to avoid matching multiple elements
    const emptyState = this.titlesContainer.locator('text=No titles found').first();
    try {
      if (await emptyState.isVisible({ timeout: 2000 })) {
        return await emptyState.textContent();
      }
    } catch {
      // Element not visible, return null
    }
    return null;
  }

  async selectSource(sourceId: string) {
    const checkbox = this.page.locator(`input[name="source"][value="${sourceId}"]`);
    // Wait for checkbox to be attached to DOM
    await checkbox.waitFor({ state: 'attached', timeout: 10000 });
    if (!(await checkbox.isChecked())) {
      await checkbox.check();
    }
  }

  async deselectSource(sourceId: string) {
    const checkbox = this.page.locator(`input[name="source"][value="${sourceId}"]`);
    // Wait for checkbox to be attached to DOM
    await checkbox.waitFor({ state: 'attached', timeout: 10000 });
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

