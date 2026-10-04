import { test, expect } from '@playwright/test';

for (const locale of ['en', 'fr']) {
  for (const width of [320, 1440]) {
    test(`standalone invitation, redirect and team recovery ${locale} at ${width}px`, async ({ page }) => {
      const errors = [];
      page.on('pageerror', error => errors.push(error.message));
      await page.setViewportSize({ width, height: 1000 });
      await page.goto(`/join/assignment/preview-individual?locale=${locale}`);
      await expect(page.locator('.phx-connected')).toBeAttached();
      await expect(page.locator('#invitation-card img[alt="GradePush"]')).toBeVisible();
      await expect(page.locator('#invitation-classroom')).toContainText('420-1P1-SO');
      await expect(page.locator('#invitation-classroom')).toContainText(locale === 'fr' ? 'Automne 2026' : 'Fall 2026');
      await expect(page.locator('#invitation-card time')).toContainText(locale === 'fr' ? '18 octobre 2026' : 'October 18, 2026');
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
      await expect(page.locator('header, footer, #invitation-instructions')).toHaveCount(0);
      await expect(page.locator('#invitation-card')).not.toContainText('cegep-exemple');
      await expect(page.locator('#invitation-account')).toContainText('@camille-roy');
      await expect(page.locator('input[name="profile[name]"], input[name="profile[student_id]"]')).toHaveCount(0);
      await page.keyboard.press('Escape');
      await expect(page.locator('#invitation-card')).toBeVisible();
      await page.locator('#accept-invitation-form button[type=submit]').focus();
      await page.keyboard.press('Enter');
      await expect(page).toHaveURL(new RegExp('/student/classrooms/preview-programming/assignments/preview-individual\\?'));
      await expect(page.locator('#student-content h1')).toHaveText('Premiers pas en Python');
      await expect(page.locator('#student-content .markdown')).toContainText('À vous de jouer');
      await expect(page.locator('#invitation-card, [role=alert]')).toHaveCount(0);

      await page.goto(`/join/assignment/preview-team?locale=${locale}`);
      await expect(page.locator('.phx-connected')).toBeAttached();
      const teamName = page.locator('input[name="profile[team_name]"]');
      const team = page.locator('select[name="profile[team_id]"]');
      await expect(teamName).toHaveAttribute('required', '');
      await team.selectOption('1');
      await expect(teamName).toHaveCount(0);
      await expect(team).toHaveValue('1');
      await team.selectOption('');
      await expect(teamName).toBeVisible();
      await teamName.fill('Les Curieux');
      await page.locator('#accept-invitation-form button[type=submit]').click();
      await expect(page).toHaveURL(new RegExp('/student/classrooms/preview-programming/assignments/preview-team\\?'));
      await expect(page.locator('[data-team]')).toContainText('Les Curieux');
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);

      await page.goto(`/join/assignment/preview-full?locale=${locale}`);
      await expect(page.locator('.phx-connected')).toBeAttached();
      await team.selectOption('1');
      await expect(teamName).toHaveCount(0);
      await page.locator('#accept-invitation-form button[type=submit]').click();
      const error = page.locator('#invitation-error');
      await expect(error).toContainText(locale === 'fr' ? 'équipe est complète' : 'team is full');
      const [accountBox, errorBox, formBox] = await Promise.all([
        page.locator('#invitation-account').boundingBox(), error.boundingBox(),
        page.locator('#accept-invitation-form').boundingBox(),
      ]);
      expect(errorBox.y - (accountBox.y + accountBox.height)).toBeGreaterThanOrEqual(23);
      expect(formBox.y - (errorBox.y + errorBox.height)).toBeGreaterThanOrEqual(23);
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
      await team.selectOption('2');
      await expect(error).toHaveCount(0);
      await page.locator('#accept-invitation-form button[type=submit]').click();
      await expect(page.locator('[data-team]')).toContainText('Les Explorateurs');

      await page.goto(`/join/assignment/preview-assigned?locale=${locale}`);
      await expect(page.locator('#accept-invitation-form')).toContainText('Les Bâtisseurs');
      await expect(page.locator('select')).toHaveCount(0);
      await expect(page.locator('#accept-invitation-form button[type=submit]')).toBeEnabled();
      await page.goto(`/join/assignment/preview-waiting?locale=${locale}`);
      await expect(page.locator('#accept-invitation-form button[type=submit]')).toBeDisabled();
      await expect(page.getByRole('status')).toContainText(locale === 'fr' ? 'enseignant' : 'teacher');

      await page.goto(`/join/assignment/preview-signed-out?locale=${locale}`);
      await expect(page.locator('a[href="/auth/github"]')).toBeVisible();
      await expect(page.locator('#accept-invitation-form, header, footer')).toHaveCount(0);
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
      expect(errors).toEqual([]);
    });
  }
}
