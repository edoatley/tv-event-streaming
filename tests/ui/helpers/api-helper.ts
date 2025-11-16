import { Page } from '@playwright/test';
import * as dotenv from 'dotenv';
import * as path from 'path';

// Load environment variables
dotenv.config({ path: path.resolve(__dirname, '../.env') });

const BASE_URL = process.env.BASE_URL || '';
// API_ENDPOINT defaults to BASE_URL if not set, removing trailing slash
const API_ENDPOINT = process.env.API_ENDPOINT || (BASE_URL ? BASE_URL.replace(/\/$/, '') : '');

/**
 * Makes an API call using fetch from the browser context
 */
export async function apiCall(
  page: Page,
  endpoint: string,
  method: string = 'GET',
  body?: any,
  token?: string
): Promise<any> {
  const url = endpoint.startsWith('http') ? endpoint : `${API_ENDPOINT}${endpoint}`;

  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
  };

  if (token) {
    headers['Authorization'] = token;
  }

  const response = await page.evaluate(
    async ({ url, method, headers, body }) => {
      const response = await fetch(url, {
        method,
        headers,
        body: body ? JSON.stringify(body) : undefined,
      });

      if (!response.ok) {
        const errorText = await response.text();
        throw new Error(`API call failed: ${response.status} ${errorText}`);
      }

      const contentType = response.headers.get('content-type');
      if (contentType && contentType.includes('application/json')) {
        return await response.json();
      }
      return await response.text();
    },
    { url, method, headers, body }
  );

  return response;
}

/**
 * Sets user preferences via API
 */
export async function setUserPreferences(
  page: Page,
  token: string,
  preferences: { sources: string[]; genres: string[] }
): Promise<void> {
  await apiCall(page, '/preferences', 'PUT', preferences, token);
}

/**
 * Gets user preferences via API
 */
export async function getUserPreferences(
  page: Page,
  token: string
): Promise<{ sources: string[]; genres: string[] }> {
  return await apiCall(page, '/preferences', 'GET', undefined, token);
}

/**
 * Gets sources list via API
 */
export async function getSources(page: Page): Promise<Array<{ id: string; name: string }>> {
  return await apiCall(page, '/sources', 'GET');
}

/**
 * Gets genres list via API
 */
export async function getGenres(page: Page): Promise<Array<{ id: string; name: string }>> {
  return await apiCall(page, '/genres', 'GET');
}

/**
 * Gets titles via API
 */
export async function getTitles(page: Page, token: string): Promise<any[]> {
  return await apiCall(page, '/titles', 'GET', undefined, token);
}

/**
 * Gets recommendations via API
 */
export async function getRecommendations(page: Page, token: string): Promise<any[]> {
  return await apiCall(page, '/recommendations', 'GET', undefined, token);
}

