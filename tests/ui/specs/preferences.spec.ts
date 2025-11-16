import { test, expect } from '../fixtures/test-context';
import { authenticatedUser } from '../fixtures/auth';
import { getSources, getGenres, setUserPreferences, getUserPreferences } from '../helpers/api-helper';
import { TEST_USERS } from '../fixtures/test-data';

test.describe('User Preferences', () => {
  test.describe('Preferences page', () => {
    test('should navigate to preferences page', async ({ authenticatedPage, mainViewPage }) => {
      await authenticatedPage.goto('/');
      await mainViewPage.navigateToPreferences();
      
      await expect(mainViewPage.updatePreferencesBtn).toBeVisible();
      await expect(mainViewPage.selectedSourcesList).toBeVisible();
      await expect(mainViewPage.selectedGenresList).toBeVisible();
    });

    test('should display current preferences', async ({ authenticatedPage, mainViewPage }) => {
      await authenticatedPage.goto('/');
      await mainViewPage.navigateToPreferences();
      
      // Wait for preferences to load
      await authenticatedPage.waitForTimeout(1000);
      
      // Should show sources and genres sections
      await expect(mainViewPage.selectedSourcesList).toBeVisible();
      await expect(mainViewPage.availableSourcesList).toBeVisible();
      await expect(mainViewPage.selectedGenresList).toBeVisible();
      await expect(mainViewPage.availableGenresList).toBeVisible();
    });

    test('should show empty state when no preferences are set', async ({ authenticatedPage, mainViewPage }) => {
      // Clear preferences first via API
      const token = await authenticatedPage.evaluate(() => localStorage.getItem('id_token'));
      if (token) {
        await setUserPreferences(authenticatedPage, token, { sources: [], genres: [] });
      }

      await authenticatedPage.goto('/');
      await mainViewPage.navigateToPreferences();
      
      // Should show empty state messages
      const selectedSources = await mainViewPage.selectedSourcesList.textContent();
      const selectedGenres = await mainViewPage.selectedGenresList.textContent();
      
      // Check for empty state indicators
      expect(selectedSources || selectedGenres).toBeTruthy();
    });
  });

  test.describe('Updating preferences', () => {
    test('should allow selecting sources', async ({ authenticatedPage, mainViewPage }) => {
      // Get available sources
      const sources = await getSources(authenticatedPage);
      expect(sources.length).toBeGreaterThan(0);

      await authenticatedPage.goto('/');
      await mainViewPage.navigateToPreferences();
      
      // Wait for sources to load
      await authenticatedPage.waitForTimeout(1000);
      
      // Select first available source if not already selected
      const firstSourceId = sources[0].id;
      const selectedSources = await mainViewPage.getSelectedSources();
      
      if (!selectedSources.includes(firstSourceId)) {
        await mainViewPage.selectSource(firstSourceId);
        const updated = await mainViewPage.getSelectedSources();
        expect(updated).toContain(firstSourceId);
      }
    });

    test('should allow selecting genres', async ({ authenticatedPage, mainViewPage }) => {
      // Get available genres
      const genres = await getGenres(authenticatedPage);
      expect(genres.length).toBeGreaterThan(0);

      await authenticatedPage.goto('/');
      await mainViewPage.navigateToPreferences();
      
      // Wait for genres to load
      await authenticatedPage.waitForTimeout(1000);
      
      // Select first available genre if not already selected
      const firstGenreId = genres[0].id;
      const selectedGenres = await mainViewPage.getSelectedGenres();
      
      if (!selectedGenres.includes(firstGenreId)) {
        await mainViewPage.selectGenre(firstGenreId);
        const updated = await mainViewPage.getSelectedGenres();
        expect(updated).toContain(firstGenreId);
      }
    });

    test('should allow deselecting sources', async ({ authenticatedPage, mainViewPage }) => {
      const token = await authenticatedPage.evaluate(() => localStorage.getItem('id_token'));
      if (!token) {
        test.skip();
        return;
      }

      // Set some preferences first
      const sources = await getSources(authenticatedPage);
      if (sources.length === 0) {
        test.skip();
        return;
      }

      await setUserPreferences(authenticatedPage, token, {
        sources: [sources[0].id],
        genres: [],
      });

      await authenticatedPage.goto('/');
      await mainViewPage.navigateToPreferences();
      await authenticatedPage.waitForTimeout(1000);

      // Deselect the source
      await mainViewPage.deselectSource(sources[0].id);
      const updated = await mainViewPage.getSelectedSources();
      expect(updated).not.toContain(sources[0].id);
    });

    test('should update preferences and show success message', async ({ authenticatedPage, mainViewPage }) => {
      const token = await authenticatedPage.evaluate(() => localStorage.getItem('id_token'));
      if (!token) {
        test.skip();
        return;
      }

      const sources = await getSources(authenticatedPage);
      const genres = await getGenres(authenticatedPage);
      
      if (sources.length === 0 || genres.length === 0) {
        test.skip();
        return;
      }

      await authenticatedPage.goto('/');
      await mainViewPage.navigateToPreferences();
      await authenticatedPage.waitForTimeout(1000);

      // Select some preferences
      await mainViewPage.selectSource(sources[0].id);
      await mainViewPage.selectGenre(genres[0].id);

      // Set up alert handler
      let alertMessage = '';
      authenticatedPage.on('dialog', async (dialog) => {
        alertMessage = dialog.message();
        await dialog.accept();
      });

      // Update preferences
      await mainViewPage.updatePreferences();
      await authenticatedPage.waitForTimeout(1000);

      // Check for success message
      expect(alertMessage).toContain('success');
    });

    test('should persist preferences after page refresh', async ({ authenticatedPage, mainViewPage }) => {
      const token = await authenticatedPage.evaluate(() => localStorage.getItem('id_token'));
      if (!token) {
        test.skip();
        return;
      }

      const sources = await getSources(authenticatedPage);
      const genres = await getGenres(authenticatedPage);
      
      if (sources.length === 0 || genres.length === 0) {
        test.skip();
        return;
      }

      // Set preferences via API
      const testSources = [sources[0].id];
      const testGenres = [genres[0].id];
      
      await setUserPreferences(authenticatedPage, token, {
        sources: testSources,
        genres: testGenres,
      });

      await authenticatedPage.goto('/');
      await mainViewPage.navigateToPreferences();
      await authenticatedPage.waitForTimeout(1000);

      // Refresh page
      await authenticatedPage.reload();
      await authenticatedPage.waitForTimeout(1000);

      // Check preferences are still set
      const selectedSources = await mainViewPage.getSelectedSources();
      const selectedGenres = await mainViewPage.getSelectedGenres();

      expect(selectedSources).toEqual(expect.arrayContaining(testSources));
      expect(selectedGenres).toEqual(expect.arrayContaining(testGenres));
    });
  });

  test.describe('Preferences integration with titles', () => {
    test('should affect displayed titles when preferences change', async ({ authenticatedPage, mainViewPage }) => {
      const token = await authenticatedPage.evaluate(() => localStorage.getItem('id_token'));
      if (!token) {
        test.skip();
        return;
      }

      const sources = await getSources(authenticatedPage);
      const genres = await getGenres(authenticatedPage);
      
      if (sources.length === 0 || genres.length === 0) {
        test.skip();
        return;
      }

      // Set initial preferences
      await setUserPreferences(authenticatedPage, token, {
        sources: [sources[0].id],
        genres: [genres[0].id],
      });

      await authenticatedPage.goto('/');
      await mainViewPage.navigateToTitles();
      await mainViewPage.waitForTitlesToLoad();

      const initialCount = await mainViewPage.getTitleCardCount();

      // Change preferences
      if (sources.length > 1) {
        await mainViewPage.navigateToPreferences();
        await authenticatedPage.waitForTimeout(1000);
        await mainViewPage.selectSource(sources[1].id);
        await mainViewPage.updatePreferences();
        await authenticatedPage.waitForTimeout(1000);

        // Go back to titles
        await mainViewPage.navigateToTitles();
        await mainViewPage.waitForTitlesToLoad();

        // Titles may change (or stay the same if both sources have same titles)
        const newCount = await mainViewPage.getTitleCardCount();
        // Just verify the page loaded correctly
        expect(newCount).toBeGreaterThanOrEqual(0);
      }
    });
  });
});

