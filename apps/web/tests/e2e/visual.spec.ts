import { test, expect } from '@playwright/test';

// Visual regression for the ContactLogo web app's key screens. Baselines are
// committed under ./visual.spec.ts-snapshots and compared on every run (CI
// runs `npx playwright test`, which includes this file). Keep screens
// deterministic: mask anything live/animated rather than snapshotting it raw.
test.describe('visual', () => {
  test('homepage idle state', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await expect(page.locator('#app')).not.toBeEmpty();
    // The idle screen is static (upload prompt + header); full-page shot.
    await expect(page).toHaveScreenshot('homepage.png', { fullPage: true });
  });

  test('settings panel', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await page.getByRole('button', { name: 'Settings' }).click();
    await expect(page.getByRole('heading', { name: 'Settings' })).toBeVisible();
    await expect(page).toHaveScreenshot('settings.png', { fullPage: true });
  });
});
