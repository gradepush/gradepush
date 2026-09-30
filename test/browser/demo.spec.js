import { test, expect } from '@playwright/test';

for (const role of ['teacher', 'student']) {
  test(`CSP permits ${role} sign-in and classroom navigation`, async ({ page }) => {
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.addInitScript(() => {
      window.cspViolations = [];
      document.addEventListener('securitypolicyviolation', event => {
        window.cspViolations.push(event.effectiveDirective);
      });
    });
    await page.goto('/demo?locale=en');
    await expect(page.locator('.phx-connected')).toBeAttached();
    await page.getByRole('button', {name: `Continue as a ${role}`}).click();
    const prefix = role === 'teacher' ? '/classrooms' : '/student/classrooms';
    await expect(page).toHaveURL(new RegExp(`${prefix}$`));
    await expect(page.locator('.phx-connected')).toBeAttached();
    expect(await page.evaluate(() => window.cspViolations)).toEqual([]);
    await page.locator(`main a[href^="${prefix}/"]`).first().click();
    await expect(page).toHaveURL(new RegExp(`${prefix}/[^/]+$`));
    await expect(page.locator('.phx-connected')).toBeAttached();
    await expect(page.locator('main')).toBeVisible();
    expect(await page.evaluate(() => window.cspViolations)).toEqual([]);
    expect(errors).toEqual([]);
  });
}
