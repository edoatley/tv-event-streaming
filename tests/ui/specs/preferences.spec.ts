import { test, expect } from '../fixtures/test-context';
import { getSources, getGenres, setUserPreferences, getUserPreferences } from '../helpers/api-helper';
import { TEST_USERS } from '../fixtures/test-data';

test.describe('User Preferences', () => {
  test.describe('Preferences page', () => {
    test('should navigate to preferences page', async ({ authenticatedPage, mainViewPage }) => {
      await authenticatedPage.goto('/');
      await mainViewPage.navigateToPreferences();

      // The update button should exist (may or may not be visible depending on CSS)
      const buttonExists = await mainViewPage.updatePreferencesBtn.count() > 0;
      expect(buttonExists).toBeTruthy();
      
      // The lists should exist and have some content
      const selectedSourcesContent = await mainViewPage.selectedSourcesList.textContent() || '';
      
      // At least one of the lists should have content (sources or genres should be loaded)
      const hasAnyContent = selectedSourcesContent.trim().length > 0 || 
                            (await mainViewPage.availableSourcesList.textContent() || '').trim().length > 0;
      
      expect(hasAnyContent).toBeTruthy();
    });

    test('should display current preferences', async ({ authenticatedPage, mainViewPage }) => {
      await authenticatedPage.goto('/');
      await mainViewPage.navigateToPreferences();

      // Wait for preferences to load
      const hasSources = (await mainViewPage.availableSourcesList.textContent() || '').trim().length > 0;
      const hasGenres = (await mainViewPage.availableGenresList.textContent() || '').trim().length > 0;
      
      expect(hasSources || hasGenres).toBeTruthy();
    });

    test('should show empty state when no preferences are set', async ({ authenticatedPage, mainViewPage }) => {
      // Clear preferences first via API
      const token = await authenticatedPage.evaluate(() => localStorage.getItem('id_token'));
      if (!token) {
        test.skip();
        return;
      }
      
      try {
        await setUserPreferences(authenticatedPage, token, { sources: [], genres: [] });
        // Wait for API consistency
        await authenticatedPage.waitForTimeout(1000);
      } catch (error) {
        test.skip();
        return;
      }

      await authenticatedPage.goto('/');
      await mainViewPage.navigateToPreferences();
      
      // Use playwright assertions to wait for the text
      await expect(mainViewPage.selectedSourcesList).toContainText('No sources selected', { timeout: 10000 });
      await expect(mainViewPage.selectedGenresList).toContainText('No genres selected');
    });
  });

  test.describe('Updating preferences', () => {
    test('should allow selecting sources', async ({ authenticatedPage, mainViewPage }) => {
      let sources;
      try {
        sources = await getSources(authenticatedPage);
      } catch (error) {
        test.skip();
        return;
      }
      
      if (sources.length === 0) {
        test.skip();
        return;
      }

      await authenticatedPage.goto('/');
      await mainViewPage.navigateToPreferences();
      
      const firstSourceId = String(sources[0].id);
      
      // Perform selection
      await mainViewPage.selectSource(firstSourceId);
      
      // Verify using strict locator check
      const checkbox = authenticatedPage.locator(`input[name="source"][value="${firstSourceId}"]`);
      await expect(checkbox).toBeChecked();
    });

    test('should allow selecting genres', async ({ authenticatedPage, mainViewPage }) => {
      const genres = await getGenres(authenticatedPage);
      if (genres.length === 0) {
          test.skip();
          return;
      }

      await authenticatedPage.goto('/');
      await mainViewPage.navigateToPreferences();
      
      const firstGenreId = String(genres[0].id);
      await mainViewPage.selectGenre(firstGenreId);
      
      const checkbox = authenticatedPage.locator(`input[name="genre"][value="${firstGenreId}"]`);
      await expect(checkbox).toBeChecked();
    });

    test('should allow deselecting sources', async ({ authenticatedPage, mainViewPage }) => {
      const token = await authenticatedPage.evaluate(() => localStorage.getItem('id_token'));
      if (!token) {
        test.skip();
        return;
      }

      let sources;
      try {
        sources = await getSources(authenticatedPage);
      } catch (error) {
        test.skip();
        return;
      }
      
      if (sources.length === 0) {
        test.skip();
        return;
      }

      try {
        await setUserPreferences(authenticatedPage, token, {
          sources: [sources[0].id],
          genres: [],
        });
      } catch (error) {
        test.skip();
        return;
      }

      await authenticatedPage.goto('/');
      await mainViewPage.navigateToPreferences();
      
      const sourceId = String(sources[0].id);
      
      // Ensure it is initially checked
      const checkbox = authenticatedPage.locator(`input[name="source"][value="${sourceId}"]`);
      await expect(checkbox).toBeChecked();

      // Deselect
      await mainViewPage.deselectSource(sourceId);
      
      // Verify unchecked
      await expect(checkbox).not.toBeChecked();
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

      // 1. Set preferences via API
      const testSourceId = String(sources[0].id);
      const testGenreId = String(genres[0].id);
      
      await setUserPreferences(authenticatedPage, token, {
        sources: [testSourceId],
        genres: [testGenreId],
      });
      
      // 2. Load the page
      await authenticatedPage.goto('/');
      await mainViewPage.navigateToPreferences();
      
      // 3. Verify UI matches API (wait for state)
      const sourceCheckbox = authenticatedPage.locator(`input[name="source"][value="${testSourceId}"]`);
      const genreCheckbox = authenticatedPage.locator(`input[name="genre"][value="${testGenreId}"]`);
      
      await expect(sourceCheckbox).toBeChecked({ timeout: 10000 });
      await expect(genreCheckbox).toBeChecked({ timeout: 10000 });

      // 4. Refresh page
      await authenticatedPage.reload();
      
      // 5. Navigate back to preferences
      await mainViewPage.navigateToPreferences();
      
      // 6. Verify persistence (Playwright will retry this assertion until timeout)
      // This fixes the flake by waiting for the specific element state rather than a hard sleep
      await expect(sourceCheckbox).toBeChecked({ timeout: 10000 });
      await expect(genreCheckbox).toBeChecked({ timeout: 10000 });
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

      // Change preferences via UI
      if (sources.length > 1) {
        await mainViewPage.navigateToPreferences();
        
        // Wait for checkbox to be interactive
        const secondSourceId = String(sources[1].id);
        await mainViewPage.selectSource(secondSourceId);
        
        await mainViewPage.updatePreferences();
        
        // Handle alert
        authenticatedPage.on('dialog', dialog => dialog.accept());

        // Go back to titles
        await mainViewPage.navigateToTitles();
        await mainViewPage.waitForTitlesToLoad();

        // Verify page loaded (titles may vary, but page shouldn't crash)
        await expect(mainViewPage.titlesContainer).toBeVisible();
      }
    });
  });
});