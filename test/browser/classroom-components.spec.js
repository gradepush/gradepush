import { test, expect } from '@playwright/test';

// UI_PREVIEW uses local fixtures. These tests never create GitHub invitations or repositories.
for (const locale of ['en', 'fr']) {
  for (const width of [320, 1440]) {
    test(`copyable invitations wrap and copy their complete value (${locale}, ${width}px)`, async ({ page, context }) => {
      await page.setViewportSize({ width, height: 1000 });
      await context.grantPermissions(['clipboard-read', 'clipboard-write']);
      for (const [path, trigger, id] of [
        ['/classrooms/programming/assignments/loops', '[data-ui~=assignment-heading] button', 'assignment-invitation'],
        ['/admin/institution', locale === 'fr' ? 'button:text-is("Inviter un enseignant")' : 'button:text-is("Invite a teacher")', 'teacher-invitation'],
      ]) {
        await page.goto(`${path}?locale=${locale}`);
        await expect(page.locator('.phx-connected')).toBeAttached();
        await page.locator(trigger).click();
        const field = page.locator(`#${id}`);
        await expect(field).toBeVisible();
        const value = await field.getAttribute('data-copy');
        expect(value).toMatch(/^https:\/\/gradepush\.example\/join\//);
        const sizes = await field.evaluate(element => {
          const region = element.querySelector('pre');
          const dialog = element.closest('[role=dialog]');
          return { region: region.scrollWidth - region.clientWidth, dialog: dialog.scrollWidth - dialog.clientWidth,
            page: document.documentElement.scrollWidth - document.documentElement.clientWidth,
            wrapped: region.clientHeight >= 40 };
        });
        expect(sizes.region).toBeLessThanOrEqual(1);
        expect(sizes.dialog).toBeLessThanOrEqual(1);
        expect(sizes.page).toBeLessThanOrEqual(1);
        if (width === 320) expect(sizes.wrapped).toBe(true);
        await field.locator('button').click();
        await expect(field.locator('[role=status]')).toHaveText(locale === 'fr' ? 'Copié' : 'Copied');
        expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(value);
      }
    });

    test(`test cards keep settings, fit the viewport and expose validation (${locale}, ${width}px)`, async ({ page }) => {
      await page.setViewportSize({ width, height: 1000 });
      await page.goto(`/classrooms/programming/assignments/new?locale=${locale}`);
      await expect(page.locator('.phx-connected')).toBeAttached();
      await page.locator('#assignment_title').fill('Greeting lab');
      await page.locator('#assignment_autograding').check();
      await page.locator('#assignment-form button[type=submit]').click();
      const warning = page.locator('#assignment_autograding-errors');
      await expect(warning).toBeVisible();
      if (width === 1440) {
        const [label, message] = await Promise.all([
          page.locator('[data-ui=grading-toggle] label').boundingBox(), warning.boundingBox(),
        ]);
        expect(Math.abs(label.y - message.y)).toBeLessThan(8);
        expect(message.x).toBeGreaterThan(label.x + label.width);
      }
      const add = page.locator('button[phx-click=add_assignment_test]');
      await expect(add).toHaveCount(1);
      await add.click();
      await page.locator('#assignment_tests_0_name').fill('Greeting');
      const description = page.locator('#assignment_tests_0_description');
      await expect(description).toBeVisible();
      await description.fill('Checks a greeting with leading indentation.');
      await page.locator('#assignment_tests_0_type').selectOption('io');
      await page.locator('#assignment_tests_0_runtime').selectOption('python-3.14.7');
      await page.locator('#assignment_tests_0_setup_command').fill('python --version');
      await page.locator('#assignment_tests_0_command').fill('python main.py');
      await page.locator('#assignment_tests_0_input').fill('Ada');
      await page.locator('#assignment_tests_0_expected').fill('  Hello, Ada!\n');
      await expect(page.locator('#assignment_tests_0_output_comparison')).toHaveValue('trim_trailing');
      const card = page.locator('[data-ui=automatic-test]').first();
      const remove = card.locator('button[phx-click=remove_assignment_test]');
      await expect(remove).toHaveAccessibleName(locale === 'fr' ? 'Retirer le test 1' : 'Remove test 1');
      const [nameBounds, removeBounds] = await Promise.all([page.locator('#assignment_tests_0_name').boundingBox(), remove.boundingBox()]);
      const toggle = card.locator('[data-test-toggle]');
      const toggleBounds = await toggle.boundingBox();
      const cardBounds = await card.boundingBox();
      expect(removeBounds.y).toBeLessThan(nameBounds.y);
      expect(removeBounds.x).toBeGreaterThanOrEqual(toggleBounds.x + toggleBounds.width - 1);
      expect(removeBounds.width).toBeGreaterThanOrEqual(44);
      expect(removeBounds.height).toBeGreaterThanOrEqual(44);
      expect(toggleBounds.height).toBeGreaterThanOrEqual(64);
      expect(toggleBounds.width / cardBounds.width).toBeGreaterThan(0.72);
      expect(await toggle.evaluate(element => getComputedStyle(element).cursor)).toBe('pointer');
      if (width === 1440) {
        const fields = await card.locator('[data-ui=test-name-fields]').boundingBox();
        const bounds = await card.boundingBox();
        expect(fields.width / bounds.width).toBeLessThan(0.55);
        const [type, runtime] = await Promise.all([
          page.locator('#assignment_tests_0_type').boundingBox(), page.locator('#assignment_tests_0_runtime').boundingBox(),
        ]);
        expect(type.y).toBe(runtime.y);
      }
      expect(await card.evaluate(element => element.scrollWidth - element.clientWidth)).toBeLessThanOrEqual(1);
      expect(await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)).toBeLessThanOrEqual(1);

      await page.locator('#assignment_tests_0_points').fill('11');
      await page.locator('#assignment_tests_0_points').press('Tab');
      await expect(page.getByText(locale === 'fr' ? '11 points au total' : '11 points total', {exact:true})).toBeVisible();
      await expect(toggle).toContainText('Greeting');
      await expect(toggle.locator('[data-test-points]')).toHaveText('11 points');
      await expect(toggle).toHaveAttribute('aria-expanded', 'true');
      await toggle.focus();
      await page.keyboard.press('Space');
      await expect(toggle).toHaveAttribute('aria-expanded', 'false');
      await expect(description).toBeHidden();
      await expect(page.locator('#assignment_tests_0_name')).toBeHidden();
      await expect(page.locator('#assignment_tests_0_points')).toBeHidden();
      await expect(remove).toBeVisible();
      expect((await card.boundingBox()).height).toBeLessThan(110);
      await page.locator('#assignment_title').fill('Greeting lab updated');
      await expect(toggle).toHaveAttribute('aria-expanded', 'false');
      await expect(description).toBeHidden();
      await toggle.focus();
      await page.keyboard.press('Enter');
      await expect(description).toBeVisible();

      const timeout = page.locator('#assignment_tests_0_timeout_seconds');
      await expect(timeout).toBeVisible();
      await timeout.fill('90');
      await page.locator('#assignment_tests_0_output_comparison').selectOption('regex');
      await expect(page.locator('#assignment_tests_0_expected')).toHaveAccessibleName(locale === 'fr' ? 'Expression attendue' : 'Expected pattern');
      await page.locator('#assignment_tests_0_expected').fill('^  Hello, Ada!\\n$');
      const typeDimensions = await page.locator('#assignment_tests_0_type').evaluate(element => {
        const bounds = element.getBoundingClientRect();
        return { x: bounds.x, y: bounds.y + scrollY, width: bounds.width, height: bounds.height };
      });
      const runtimeDimensions = await page.locator('#assignment_tests_0_runtime').evaluate(element => {
        const bounds = element.getBoundingClientRect();
        return { x: bounds.x, y: bounds.y + scrollY, width: bounds.width, height: bounds.height };
      });
      await page.locator('#assignment_tests_0_type').selectOption('file');
      await expect(page.locator('#assignment_tests_0_path')).toBeVisible();
      const fileTypeDimensions = await page.locator('#assignment_tests_0_type').evaluate(element => {
        const bounds = element.getBoundingClientRect();
        return { x: bounds.x, y: bounds.y + scrollY, width: bounds.width, height: bounds.height };
      });
      for (const dimension of ['x', 'y', 'width', 'height']) {
        expect(Math.abs(fileTypeDimensions[dimension] - typeDimensions[dimension])).toBeLessThanOrEqual(1);
      }
      await expect(description).toHaveValue('Checks a greeting with leading indentation.');
      await expect(page.locator('#assignment_tests_0_name')).toHaveValue('Greeting');
      await page.locator('#assignment_tests_0_type').selectOption('io');
      await expect(page.locator('#assignment_tests_0_setup_command')).toHaveValue('python --version');
      await expect(page.locator('#assignment_tests_0_runtime')).toHaveValue('python-3.14.7');
      const restoredRuntimeDimensions = await page.locator('#assignment_tests_0_runtime').evaluate(element => {
        const bounds = element.getBoundingClientRect();
        return { x: bounds.x, y: bounds.y + scrollY, width: bounds.width, height: bounds.height };
      });
      for (const dimension of ['x', 'y', 'width', 'height']) {
        expect(Math.abs(restoredRuntimeDimensions[dimension] - runtimeDimensions[dimension])).toBeLessThanOrEqual(1);
      }
      const regexHint = page.locator('#assignment_tests_0-comparison-hint');
      await expect(regexHint.locator('strong')).toHaveText(locale === 'fr'
        ? 'Saisissez l’expression régulière dans « Expression attendue ».'
        : 'Enter the regular expression in “Expected pattern”.');
      await expect(page.locator('#assignment_tests_0_expected')).toHaveAccessibleDescription(await regexHint.innerText());
      await expect(page.locator('#assignment_tests_0_output_comparison')).toHaveAccessibleDescription(await regexHint.innerText());
      const [comparisonBounds, hintBounds] = await Promise.all([
        page.locator('#assignment_tests_0_output_comparison').boundingBox(), regexHint.boundingBox(),
      ]);
      expect(hintBounds.y).toBeGreaterThanOrEqual(comparisonBounds.y + comparisonBounds.height);
      expect(Math.abs(hintBounds.x - comparisonBounds.x)).toBeLessThanOrEqual(1);
      await expect(regexHint).not.toContainText(/10 seconds|10 secondes|8 MiB|8 Mio/);
      await page.locator('#assignment_tests_0_expected').fill('  Hello, Ada!\n');
      await page.locator('#assignment_tests_0_output_comparison').selectOption('exact');
      await expect(regexHint.locator('strong')).toBeHidden();
      const header = await toggle.boundingBox();
      await toggle.click({position:{x:header.width * 0.7,y:header.height / 2}});
      await expect(description).toBeHidden();
      await add.click();
      const second = page.locator('[data-ui=automatic-test]').nth(1);
      await expect(second.locator('[data-test-toggle]')).toHaveAttribute('aria-expanded', 'true');
      await expect(toggle).toHaveAttribute('aria-expanded', 'false');
      await second.locator('input[id$=_name]').fill('README');
      await second.locator('textarea[id$=_description]').fill('Required project instructions.');
      await second.locator('input[id$=_points]').fill('5');
      await second.locator('select[id$=_type]').selectOption('file');
      await expect(second.locator('input[id$=_path]')).toBeVisible();
      await second.locator('input[id$=_path]').fill('README.md');
      await expect(second.locator('select[id$=_type]')).toHaveValue('file');
      await second.locator('[data-test-toggle]').click();
      await expect(second.locator('[data-test-toggle]')).toHaveAttribute('aria-expanded', 'false');
      await second.locator('button[phx-click=remove_assignment_test]').click();
      await expect(page.locator('[data-ui=automatic-test]')).toHaveCount(1);
      await expect(toggle).toHaveAttribute('aria-expanded', 'false');
      await page.locator('#assignment-form button[type=submit]').click();
      await expect(page).toHaveURL(/\/assignments\/[^/?]+(?:\?.*)?$/);
      await page.getByRole('link', {name: locale === 'fr' ? 'Modifier le devoir' : 'Edit assignment', exact: true}).click();
      await expect(page.locator('.phx-connected')).toBeAttached();
      await expect(page.locator('#assignment_tests_0_runtime')).toHaveValue('python-3.14.7');
      await expect(page.locator('#assignment_tests_0_output_comparison')).toHaveValue('exact');
      await expect(description).toHaveValue('Checks a greeting with leading indentation.');
      await expect(page.locator('#assignment_tests_0_setup_command')).toHaveValue('python --version');
      await expect(timeout).toHaveValue('90');
      await expect(page.locator('#assignment_tests_0_expected')).toHaveValue('  Hello, Ada!\n');
      await timeout.fill('29');
      await expect(timeout).toHaveAttribute('aria-invalid', 'true');
      await toggle.click();
      await expect(timeout).toBeHidden();
      // HTML validation must reveal a hidden invalid input before the browser focuses it.
      await page.locator('#assignment-form button[type=submit]').click();
      await expect(timeout).toBeVisible();
      await expect(timeout).toBeFocused();
      await toggle.click();
      await expect(timeout).toBeHidden();
      // Submit programmatically through the real form event to verify server validation as well as HTML bounds.
      await page.locator('#assignment-form').evaluate(form => form.dispatchEvent(new Event('submit', {bubbles: true, cancelable: true})));
      await expect(timeout).toHaveAttribute('aria-invalid', 'true');
      await expect(toggle).toHaveAttribute('aria-expanded', 'true');
      await expect(timeout).toBeVisible();
      await page.locator('button[phx-click=remove_assignment_test]').click();
      await expect(page.locator('[data-ui=automatic-test]')).toHaveCount(0);
      await add.click();
      await page.locator('#assignment_tests_0_type').selectOption('file');
      await expect(page.locator('#assignment_tests_0_description')).toBeVisible();
      await expect(page.locator('#assignment_tests_0_runtime')).toBeHidden();
      await expect(page.locator('#assignment_tests_0_setup_command')).toBeHidden();
      await expect(page.locator('#assignment_tests_0_path')).toBeVisible();
    });
  }
}
