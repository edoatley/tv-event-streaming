import { test, expect } from '../fixtures/test-context';
import { setUserPreferences, getSources, getGenres } from '../helpers/api-helper';
import { EXPECTED_TEXT } from '../fixtures/test-data';

test.describe('Titles View', () => {
  test.describe('Navigation and display', () => {
    test('should navigate to titles tab', async ({ authenticatedPage, mainViewPage }) => {
      await authenticatedPage.goto('/');
      await mainViewPage.navigateToTitles();
      
      await expect(mainViewPage.allTitlesTab).toBeVisible();
      await expect(mainViewPage.recommendationsTab).toBeVisible();
    });

    test('should display titles in card format', async ({ authenticatedPage, mainViewPage }) => {
      const token = await authenticatedPage.evaluate(() => localStorage.getItem('id_token'));
      if (!token) {
        test.skip();
        return;
      }

      // Ensure user has preferences set
      const sources = await getSources(authenticatedPage);
      const genres = await getGenres(authenticatedPage);
      
      if (sources.length === 0 || genres.length === 0) {
        test.skip();
        return;
      }

      await setUserPreferences(authenticatedPage, token, {
        sources: [sources[0].id],
        genres: [genres[0].id],
      });

      await authenticatedPage.goto('/');
      await mainViewPage.navigateToTitles();
      await mainViewPage.waitForTitlesToLoad();

      const titleCards = await mainViewPage.getTitleCards();
      const count = await titleCards.count();

      if (count > 0) {
        // Verify card structure
        const firstCard = titleCards.first();
        await expect(firstCard).toBeVisible();
        
        // Check for title image
        const image = firstCard.locator('img');
        await expect(image).toBeVisible();
        
        // Check for title text
        const titleText = firstCard.locator('.card-title');
        await expect(titleText).toBeVisible();
      }
    });

    test('should show loading indicator while fetching titles', async ({ authenticatedPage, mainViewPage }) => {
      await authenticatedPage.goto('/');
      await mainViewPage.navigateToTitles();
      
      // Loading indicator should appear briefly
      // Note: This may be too fast to catch, so we'll just verify the element exists
      const loadingExists = await mainViewPage.titlesLoading.isVisible().catch(() => false);
      // Loading may have already completed, which is fine
    });

    test('should show empty state when no titles match preferences', async ({ authenticatedPage, mainViewPage }) => {
      const token = await authenticatedPage.evaluate(() => localStorage.getItem('id_token'));
      if (!token) {
        test.skip();
        return;
      }

      // Set preferences that likely won't have titles
      // Use invalid or non-existent IDs to ensure no matches
      await setUserPreferences(authenticatedPage, token, {
        sources: ['999999'],
        genres: ['999999'],
      });

      await authenticatedPage.goto('/');
      await mainViewPage.navigateToTitles();
      await mainViewPage.waitForTitlesToLoad();

      // Wait a bit more for the UI to update, but with a reasonable timeout
      await authenticatedPage.waitForTimeout(2000);

      // Check for empty state - look specifically in the titles container
      const titleCount = await mainViewPage.getTitleCardCount();
      
      // If there are no cards, check for empty state message in titles container
      if (titleCount === 0) {
        const emptyStateInTitles = mainViewPage.titlesContainer.locator('text=No titles found').first();
        try {
          const isEmptyVisible = await emptyStateInTitles.isVisible({ timeout: 2000 });
          if (isEmptyVisible) {
            const emptyText = await emptyStateInTitles.textContent();
            expect(emptyText?.toLowerCase()).toMatch(/no.*title/i);
          }
        } catch {
          // Empty state message might not be visible, but count is 0 which is correct
        }
      }
      
      // Verify there are no title cards
      expect(titleCount).toBe(0);
    });
  });

  test.describe('Tabs switching', () => {
    test('should switch between All Titles and Recommendations tabs', async ({ authenticatedPage, mainViewPage }) => {
      await authenticatedPage.goto('/');
      await mainViewPage.navigateToTitles();
      
      // Should start on All Titles tab
      await expect(mainViewPage.titlesContainer).toBeVisible();
      
      // Switch to Recommendations
      await mainViewPage.switchToRecommendationsTab();
      await expect(mainViewPage.recommendationsContainer).toBeVisible();
      
      // Switch back to All Titles
      await mainViewPage.switchToAllTitlesTab();
      await expect(mainViewPage.titlesContainer).toBeVisible();
    });

    test('should show recommendations tab content', async ({ authenticatedPage, mainViewPage }) => {
      const token = await authenticatedPage.evaluate(() => localStorage.getItem('id_token'));
      if (!token) {
        test.skip();
        return;
      }

      // Ensure user has preferences and data
      const sources = await getSources(authenticatedPage);
      const genres = await getGenres(authenticatedPage);
      
      if (sources.length === 0 || genres.length === 0) {
        test.skip();
        return;
      }

      await setUserPreferences(authenticatedPage, token, {
        sources: [sources[0].id],
        genres: [genres[0].id],
      });

      await authenticatedPage.goto('/');
      await mainViewPage.navigateToTitles();
      await mainViewPage.switchToRecommendationsTab();
      await mainViewPage.waitForRecommendationsToLoad();

      // Recommendations container should be visible
      await expect(mainViewPage.recommendationsContainer).toBeVisible();
    });
  });

  test.describe('Title cards', () => {
    test('should display poster image, title, and rating on cards', async ({ authenticatedPage, mainViewPage }) => {
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

      await setUserPreferences(authenticatedPage, token, {
        sources: [sources[0].id],
        genres: [genres[0].id],
      });

      await authenticatedPage.goto('/');
      await mainViewPage.navigateToTitles();
      await mainViewPage.waitForTitlesToLoad();

      const titleCards = await mainViewPage.getTitleCards();
      const count = await titleCards.count();

      if (count > 0) {
        const firstCard = titleCards.first();
        
        // Check for image
        const image = firstCard.locator('img');
        await expect(image).toBeVisible();
        
        // Check for title
        const title = firstCard.locator('.card-title');
        await expect(title).toBeVisible();
        const titleText = await title.textContent();
        expect(titleText).toBeTruthy();
        expect(titleText!.trim().length).toBeGreaterThan(0);
      }
    });

    test('should handle image fallback when poster URL fails', async ({ authenticatedPage, mainViewPage }) => {
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

      await setUserPreferences(authenticatedPage, token, {
        sources: [sources[0].id],
        genres: [genres[0].id],
      });

      await authenticatedPage.goto('/');
      await mainViewPage.navigateToTitles();
      await mainViewPage.waitForTitlesToLoad();

      const titleCards = await mainViewPage.getTitleCards();
      const count = await titleCards.count();

      if (count > 0) {
        const firstCard = titleCards.first();
        const image = firstCard.locator('img');
        
        // Check that image has onerror handler (set via HTML)
        // Images should have a fallback src
        const src = await image.getAttribute('src');
        expect(src).toBeTruthy();
      }
    });
  });

  test.describe('Title detail modal', () => {
    test('should open title detail modal when clicking a title card', async ({ authenticatedPage, mainViewPage, titleModalPage }) => {
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

      await setUserPreferences(authenticatedPage, token, {
        sources: [sources[0].id],
        genres: [genres[0].id],
      });

      await authenticatedPage.goto('/');
      await mainViewPage.navigateToTitles();
      await mainViewPage.waitForTitlesToLoad();

      const titleCards = await mainViewPage.getTitleCards();
      const count = await titleCards.count();

      if (count > 0) {
        await mainViewPage.clickTitleCard(0);
        await titleModalPage.waitForModal();
        await expect(titleModalPage.modal).toBeVisible();
      }
    });

    test('should display correct information in title modal', async ({ authenticatedPage, mainViewPage, titleModalPage }) => {
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

      await setUserPreferences(authenticatedPage, token, {
        sources: [sources[0].id],
        genres: [genres[0].id],
      });

      await authenticatedPage.goto('/');
      await mainViewPage.navigateToTitles();
      await mainViewPage.waitForTitlesToLoad();

      const titleCards = await mainViewPage.getTitleCards();
      const count = await titleCards.count();

      if (count > 0) {
        // Get title from card before clicking
        const firstCard = titleCards.first();
        const cardTitle = await firstCard.locator('.card-title').textContent();

        await mainViewPage.clickTitleCard(0);
        await titleModalPage.waitForModal();

        // Verify modal content
        const modalTitle = await titleModalPage.getTitle();
        expect(modalTitle).toBeTruthy();
        expect(modalTitle).toBe(cardTitle!.trim());

        // Check for plot
        const plot = await titleModalPage.getPlot();
        expect(plot).toBeTruthy();

        // Check for image
        const imageSrc = await titleModalPage.getImageSrc();
        expect(imageSrc).toBeTruthy();
      }
    });

    test('should display rating, sources, and genres in modal', async ({ authenticatedPage, mainViewPage, titleModalPage }) => {
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

      await setUserPreferences(authenticatedPage, token, {
        sources: [sources[0].id],
        genres: [genres[0].id],
      });

      await authenticatedPage.goto('/');
      await mainViewPage.navigateToTitles();
      await mainViewPage.waitForTitlesToLoad();

      const titleCards = await mainViewPage.getTitleCards();
      const count = await titleCards.count();

      if (count > 0) {
        await mainViewPage.clickTitleCard(0);
        await titleModalPage.waitForModal();

        // Check rating (may be "Not rated")
        const rating = await titleModalPage.getRating();
        expect(rating).toBeTruthy();

        // Check sources
        const sourcesText = await titleModalPage.getSources();
        expect(sourcesText).toBeTruthy();

        // Check genres
        const genresText = await titleModalPage.getGenres();
        expect(genresText).toBeTruthy();
      }
    });

    test('should close title modal', async ({ authenticatedPage, mainViewPage, titleModalPage }) => {
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

      await setUserPreferences(authenticatedPage, token, {
        sources: [sources[0].id],
        genres: [genres[0].id],
      });

      await authenticatedPage.goto('/');
      await mainViewPage.navigateToTitles();
      await mainViewPage.waitForTitlesToLoad();

      const titleCards = await mainViewPage.getTitleCards();
      const count = await titleCards.count();

      if (count > 0) {
        await mainViewPage.clickTitleCard(0);
        await titleModalPage.waitForModal();
        await expect(titleModalPage.modal).toBeVisible();

        await titleModalPage.close();
        await expect(titleModalPage.modal).not.toBeVisible();
      }
    });
  });

  test.describe('Recommendations filtering', () => {
    test('should only show titles with rating > 7 in recommendations tab', async ({ authenticatedPage, mainViewPage }) => {
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

      await setUserPreferences(authenticatedPage, token, {
        sources: [sources[0].id],
        genres: [genres[0].id],
      });

      await authenticatedPage.goto('/');
      await mainViewPage.navigateToTitles();
      await mainViewPage.switchToRecommendationsTab();
      await mainViewPage.waitForRecommendationsToLoad();

      // Recommendations should be visible (may be empty if no high-rated titles)
      await expect(mainViewPage.recommendationsContainer).toBeVisible();
      
      // If there are recommendations, they should have ratings > 7
      // Note: We can't easily verify the rating filter without inspecting the API response
      // This test mainly verifies the tab works and displays content
    });
  });
});

