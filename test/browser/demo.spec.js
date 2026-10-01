import { test, expect } from '@playwright/test';

for (const locale of ['en', 'fr']) {
  for (const width of [320, 1440]) {
    test(`team tabs scroll, support the keyboard and keep the active team (${locale}, ${width}px)`, async ({ page }) => {
      await page.setViewportSize({width, height:1000});
      await page.goto(`/demo?locale=${locale}`);
      await expect(page.locator('.phx-connected')).toBeAttached();
      await page.getByRole('button', {name: locale === 'fr' ? 'Continuer comme enseignant' : 'Continue as a teacher'}).click();
      await expect(page).toHaveURL(/\/classrooms$/);
      await page.goto(`/classrooms/programming/assignments/functions?locale=${locale}`);
      await expect(page.locator('.phx-connected')).toBeAttached();
      const manage = page.getByRole('button', {name: locale === 'fr' ? 'Gérer les équipes' : 'Manage teams', exact:true});
      await manage.click();
      const dialog = page.getByRole('dialog');
      const tabs = dialog.getByRole('tab');
      const track = dialog.getByRole('tablist');
      const first = tabs.first();
      const second = tabs.nth(1);
      const last = tabs.last();
      await expect(first).toHaveAttribute('aria-selected', 'true');
      await expect(dialog.getByRole('tabpanel')).toHaveCount(1);
      await expect.poll(() => track.evaluate(el => el.scrollWidth > el.clientWidth)).toBe(true);
      await first.focus();
      await page.keyboard.press('ArrowRight');
      await expect(second).toBeFocused();
      await expect(second).toHaveAttribute('aria-selected', 'true');
      await page.keyboard.press('End');
      await expect(last).toBeFocused();
      await expect(last).toHaveAttribute('aria-selected', 'true');
      await expect.poll(() => last.evaluate(el => {
        const box = el.getBoundingClientRect(), viewport = el.parentElement.getBoundingClientRect();
        return box.left >= viewport.left && box.right <= viewport.right;
      })).toBe(true);
      await page.keyboard.press('ArrowRight');
      await expect(first).toBeFocused();
      await expect(first).toHaveAttribute('aria-selected', 'true');
      await page.keyboard.press('ArrowLeft');
      await expect(last).toBeFocused();
      await expect(last).toHaveAttribute('aria-selected', 'true');
      await page.keyboard.press('Home');
      await expect(first).toBeFocused();
      await expect(first).toHaveAttribute('aria-selected', 'true');
      await second.click();
      await expect(second).toHaveAttribute('aria-selected', 'true');
      await expect(dialog.getByRole('tabpanel')).toHaveAttribute('aria-labelledby', await second.getAttribute('id'));
      expect(await dialog.evaluate(el => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(1);
      expect(await page.evaluate(() => document.documentElement.scrollWidth - innerWidth)).toBeLessThanOrEqual(1);
      await page.keyboard.press('Escape');
      await expect(dialog).toBeHidden();
      await expect(manage).toBeFocused();
      await manage.click();
      await expect(second).toHaveAttribute('aria-selected', 'true');

      // Mutating coverage uses only a disposable local demo; deployed smoke tests remain read-only here.
      if (new URL(page.url()).hostname === 'localhost') {
        const name = `Browser team ${locale} ${width} ${Date.now()}`;
        await page.goto(`/classrooms/programming/assignments/new?locale=${locale}`);
        await expect(page.locator('.phx-connected')).toBeAttached();
        await page.locator('#assignment_title').fill(name);
        await page.locator('#assignment_kind').selectOption('team');
        await page.locator('#assignment_team_mode').selectOption('teacher');
        await page.locator('#assignment-form button[type=submit]').click();
        await expect(page.locator('#assignment-form')).toBeHidden();
        await manage.click();
        await expect(dialog.getByRole('tab')).toHaveCount(0);
        await dialog.locator('input[name="team[name]"]').fill('First team');
        await dialog.getByRole('button', {name:locale === 'fr' ? 'Créer une équipe' : 'Create team', exact:true}).click();
        await expect(dialog.getByRole('tab')).toHaveAttribute('aria-selected', 'true');
        await dialog.locator('input[name="team[name]"]').fill(name);
        await dialog.getByRole('button', {name:locale === 'fr' ? 'Créer une équipe' : 'Create team', exact:true}).click();
        const created = dialog.getByRole('tab', {name:new RegExp(name)});
        await expect(created).toHaveAttribute('aria-selected', 'true');
        const panel = dialog.getByRole('tabpanel');
        await expect(panel.getByRole('heading', {name,exact:true})).toBeVisible();
        await expect.poll(() => created.evaluate(el => {
          const box = el.getBoundingClientRect(), viewport = el.parentElement.getBoundingClientRect();
          return box.left >= viewport.left && box.right <= viewport.right;
        })).toBe(true);
        await panel.getByRole('button', {name:locale === 'fr' ? 'Ajouter à l’équipe' : 'Add to team',exact:true}).click();
        await expect(created).toContainText('1/2');
        await expect(created).toHaveAttribute('aria-selected', 'true');
        await expect(panel.locator('li')).toHaveCount(1);
        const renamed = `${name} renamed`;
        await panel.locator('button[phx-value-action="rename"]').click();
        await expect(panel.locator('input[name="team[name]"]')).toBeFocused();
        await panel.locator('input[name="team[name]"]').fill(renamed);
        await panel.locator('form[phx-submit="rename_team"] button[type="submit"]').click();
        await expect(panel.getByRole('heading', {name:renamed,exact:true})).toBeVisible();
        await expect(dialog.getByRole('tab', {name:new RegExp(renamed)})).toHaveAttribute('aria-selected', 'true');
        const remove = panel.locator('button[phx-value-action="remove"]');
        await remove.click();
        const confirmation = panel.locator('[data-ui="team-confirmation"]');
        await expect(confirmation.locator('[phx-click*="cancel_team_action"]')).toBeFocused();
        expect(await dialog.evaluate(el => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(1);
        await confirmation.locator('[phx-click*="cancel_team_action"]').click();
        await expect(panel.locator('li')).toHaveCount(1);
        await remove.click();
        await confirmation.locator('[phx-click*="confirm_team_action"]').click();
        await expect(panel.locator('li')).toHaveCount(0);
        await expect(panel.locator('select[name="student_id"]')).toBeVisible();
        await panel.getByRole('button', {name:locale === 'fr' ? 'Ajouter à l’équipe' : 'Add to team',exact:true}).click();
        await expect(panel.locator('li')).toHaveCount(1);
        await panel.locator('button[phx-value-action="delete"]').click();
        await confirmation.locator('[phx-click*="cancel_team_action"]').click();
        await expect(dialog.getByRole('tab')).toHaveCount(2);
        await panel.locator('button[phx-value-action="delete"]').click();
        await confirmation.locator('[phx-click*="confirm_team_action"]').click();
        await expect(dialog.getByRole('tab')).toHaveCount(1);
        await expect(dialog.getByRole('tab')).toHaveAttribute('aria-selected', 'true');
        await expect(panel.getByRole('heading', {name:'First team',exact:true})).toBeVisible();
        await panel.locator('button[phx-value-action="delete"]').click();
        await confirmation.locator('[phx-click*="confirm_team_action"]').click();
        await expect(dialog.getByRole('tab')).toHaveCount(0);
        await expect(dialog.locator('#new-team-name')).toBeFocused();
        expect(await dialog.evaluate(el => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(1);
      }
    });
  }
}

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
  await expect(page.locator('.phx-connected')).toBeAttached();
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
    await expect(page.locator('.phx-connected')).toBeAttached();
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
