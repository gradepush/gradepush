import { test, expect } from '@playwright/test';

for (const [role, locale] of [['teacher', 'en'], ['student', 'en'], ['teacher', 'fr'], ['student', 'fr']]) {
  test(`CSP permits ${role} sign-in and assignment navigation (${locale})`, async ({ page }) => {
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.addInitScript(() => {
      window.cspViolations = [];
      document.addEventListener('securitypolicyviolation', event => {
        window.cspViolations.push(event.effectiveDirective);
      });
    });
    await page.goto(`/demo?locale=${locale}`);
    await expect(page.locator('.phx-connected')).toBeAttached();
    const signIn = locale === 'fr'
      ? `Continuer comme ${role === 'teacher' ? 'enseignant' : 'étudiant'}`
      : `Continue as a ${role}`;
    await page.getByRole('button', {name: signIn}).click();
    const prefix = role === 'teacher' ? '/classrooms' : '/student/classrooms';
    await expect(page).toHaveURL(new RegExp(`${prefix}$`));
    await expect(page.locator('.phx-connected')).toBeAttached();
    expect(await page.evaluate(() => window.cspViolations)).toEqual([]);
    await page.locator(`main a[href^="${prefix}/"]`).first().click();
    await expect(page).toHaveURL(new RegExp(`${prefix}/[^/]+$`));
    await expect(page.locator('.phx-connected')).toBeAttached();
    await expect(page.locator('main')).toBeVisible();
    expect(await page.evaluate(() => window.cspViolations)).toEqual([]);

    const assignment = page.locator('main [data-list-row][href*="/assignments/"]').first();
    const title = await assignment.locator('h3').innerText();
    await assignment.click();
    await expect(page).toHaveURL(new RegExp(`${prefix}/[^/]+/assignments/[^/]+$`));
    await expect(page.locator('.phx-connected')).toBeAttached();
    await expect(page.getByRole('heading', {name: title, exact: true})).toBeVisible();
    expect(await page.evaluate(() => window.cspViolations)).toEqual([]);
    expect(errors).toEqual([]);
  });
}

test('teacher saves an assignment and sees the persisted title after reloading', async ({ page }) => {
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.goto('/demo?locale=en');
  await expect(page.locator('.phx-connected')).toBeAttached();
  await page.getByRole('button', {name: 'Continue as a teacher'}).click();
  await expect(page).toHaveURL(/\/classrooms$/);
  await page.locator('main a[href^="/classrooms/"]').first().click();
  await expect(page).toHaveURL(/\/classrooms\/[^/]+$/);
  const assignment = page.locator('main [data-list-row][href*="/assignments/"]').first();
  const original = await assignment.locator('h3').innerText();
  await assignment.click();
  await expect(page).toHaveURL(/\/classrooms\/[^/]+\/assignments\/[^/]+$/);
  await expect(page.getByRole('heading', {name: original, exact: true})).toBeVisible();
  const assignmentUrl = page.url();

  const saveTitle = async title => {
    await page.getByRole('link', {name: 'Edit assignment', exact: true}).click();
    await page.getByRole('textbox', {name: 'Title', exact: true}).fill(title);
    await page.getByRole('button', {name: 'Save changes', exact: true}).click();
    await expect(page).toHaveURL(assignmentUrl);
    await expect(page.getByRole('heading', {name: title, exact: true})).toBeVisible();
  };

  const updated = `${original} (browser test)`;
  await saveTitle(updated);
  await page.reload();
  await expect(page.locator('.phx-connected')).toBeAttached();
  await expect(page.getByRole('heading', {name: updated, exact: true})).toBeVisible();
  await saveTitle(original);
  expect(errors).toEqual([]);
});
