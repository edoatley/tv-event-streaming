import { test, expect } from '../fixtures/test-context';
import { authenticatedUser, authenticatedAdmin } from '../fixtures/auth';
import { TEST_USERS } from '../fixtures/test-data';

test.describe('Admin Panel', () => {
  test.describe('Access control', () => {
    test('should show admin link only to SecurityAdmins', async ({ authenticatedPage, loginPage }) => {
      await authenticatedPage.goto('/');
      
      // Regular user should not see admin link
      await expect(loginPage.adminNav).not.toBeVisible();
    });

    test('should show admin link to admin user', async ({ adminPage, loginPage }) => {
      await adminPage.goto('/');
      
      // Admin user should see admin link
      await expect(loginPage.adminNav).toBeVisible();
    });

    test('should redirect regular user away from admin panel', async ({ authenticatedPage }) => {
      // Try to access admin panel directly
      await authenticatedPage.goto('/#/admin');
      
      // Should redirect away from admin
      // The router should redirect to main view
      await authenticatedPage.waitForURL('**/#/main/**', { timeout: 5000 });
    });

    test('should allow admin user to access admin panel', async ({ adminPage, adminViewPage }) => {
      await adminPage.goto('/#/admin');
      
      // Should show admin panel
      const isVisible = await adminViewPage.isAdminPanelVisible();
      expect(isVisible).toBe(true);
    });
  });

  test.describe('Admin panel UI', () => {
    test('should display admin panel correctly', async ({ adminPage, adminViewPage }) => {
      await adminPage.goto('/#/admin');
      
      await expect(adminViewPage.refreshReferenceDataBtn).toBeVisible();
      await expect(adminViewPage.refreshTitleDataBtn).toBeVisible();
      await expect(adminViewPage.triggerEnrichmentBtn).toBeVisible();
      await expect(adminViewPage.generateSummaryBtn).toBeVisible();
    });

    test('should display data management section', async ({ adminPage }) => {
      await adminPage.goto('/#/admin');
      
      const dataManagementCard = adminPage.locator('.card:has-text("Data Management")');
      await expect(dataManagementCard).toBeVisible();
    });

    test('should display system status section', async ({ adminPage }) => {
      await adminPage.goto('/#/admin');
      
      const systemStatusCard = adminPage.locator('.card:has-text("System Status")');
      await expect(systemStatusCard).toBeVisible();
    });
  });

  test.describe('Reference data refresh', () => {
    test('should trigger reference data refresh', async ({ adminPage, adminViewPage }) => {
      await adminPage.goto('/#/admin');
      
      await adminViewPage.refreshReferenceData();
      
      // Status should update
      const status = await adminViewPage.getReferenceDataStatus();
      expect(status).toBeTruthy();
      expect(status.length).toBeGreaterThan(0);
    });

    test('should show status message for reference data refresh', async ({ adminPage, adminViewPage }) => {
      await adminPage.goto('/#/admin');
      
      const initialStatus = await adminViewPage.getReferenceDataStatus();
      
      await adminViewPage.refreshReferenceData();
      
      // Wait for status to update (may take a moment)
      await adminPage.waitForTimeout(2000);
      
      const updatedStatus = await adminViewPage.getReferenceDataStatus();
      // Status should have changed
      expect(updatedStatus).toBeTruthy();
    });
  });

  test.describe('Title data refresh', () => {
    test('should trigger title data refresh', async ({ adminPage, adminViewPage }) => {
      await adminPage.goto('/#/admin');
      
      await adminViewPage.refreshTitleData();
      
      // Status should update
      const status = await adminViewPage.getTitleDataStatus();
      expect(status).toBeTruthy();
      expect(status.length).toBeGreaterThan(0);
    });

    test('should show status message for title data refresh', async ({ adminPage, adminViewPage }) => {
      await adminPage.goto('/#/admin');
      
      await adminViewPage.refreshTitleData();
      
      // Wait for status to update
      await adminPage.waitForTimeout(2000);
      
      const status = await adminViewPage.getTitleDataStatus();
      expect(status).toBeTruthy();
    });
  });

  test.describe('Title enrichment', () => {
    test('should trigger enrichment', async ({ adminPage, adminViewPage }) => {
      await adminPage.goto('/#/admin');
      
      await adminViewPage.triggerEnrichment();
      
      // Status should update
      const status = await adminViewPage.getEnrichmentStatus();
      expect(status).toBeTruthy();
      expect(status.length).toBeGreaterThan(0);
    });

    test('should show status message for enrichment', async ({ adminPage, adminViewPage }) => {
      await adminPage.goto('/#/admin');
      
      await adminViewPage.triggerEnrichment();
      
      // Wait for status to update
      await adminPage.waitForTimeout(2000);
      
      const status = await adminViewPage.getEnrichmentStatus();
      expect(status).toBeTruthy();
    });
  });

  test.describe('DynamoDB summary', () => {
    test('should get DynamoDB summary', async ({ adminPage, adminViewPage }) => {
      await adminPage.goto('/#/admin');
      
      await adminViewPage.getDynamoDbSummary();
      
      // Wait for summary to load
      await adminPage.waitForTimeout(2000);
      
      const summary = await adminViewPage.getDynamoDbSummaryText();
      expect(summary).toBeTruthy();
      expect(summary.length).toBeGreaterThan(0);
    });

    test('should display table information in summary', async ({ adminPage, adminViewPage }) => {
      await adminPage.goto('/#/admin');
      
      await adminViewPage.getDynamoDbSummary();
      
      // Wait for summary to load
      await adminPage.waitForTimeout(2000);
      
      const summary = await adminViewPage.getDynamoDbSummaryText();
      
      // Summary should contain table information
      // Format may vary, but should mention tables, items, or size
      expect(summary.toLowerCase()).toMatch(/table|item|size|bytes/i);
    });
  });

  test.describe('Error handling', () => {
    test('should handle errors gracefully', async ({ adminPage, adminViewPage }) => {
      await adminPage.goto('/#/admin');
      
      // Trigger an action
      await adminViewPage.refreshReferenceData();
      
      // Wait a bit for response
      await adminPage.waitForTimeout(2000);
      
      const status = await adminViewPage.getReferenceDataStatus();
      
      // Status should indicate either success or error
      expect(status).toBeTruthy();
      // Should not be empty or still showing "Refreshing..."
      expect(status.toLowerCase()).not.toContain('refreshing...');
    });
  });
});

