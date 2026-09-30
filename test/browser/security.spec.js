import { test, expect } from '@playwright/test';

for (const locale of ['en', 'fr']) {
  test(`CSP permits LiveView and blocks injected scripts (${locale})`, async ({ page }) => {
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.addInitScript(() => {
      window.cspViolations = [];
      document.addEventListener('securitypolicyviolation', event => {
        window.cspViolations.push(event.effectiveDirective);
      });
    });
    const response = await page.goto(`/setup?locale=${locale}`);
    expect(response.status()).toBe(200);
    const policy = response.headers()['content-security-policy'];
    expect(policy).toContain("script-src 'self'");
    await expect(page.locator('.phx-connected')).toBeAttached();
    await expect(page.locator('#setup-form')).toBeVisible();
    await page.locator('#setup_institution_name').fill('Security browser test');
    await page.locator('#setup_setup_token').fill('invalid-token');
    await page.locator('#setup-form button[type=submit]').click();
    await expect(page.locator('[role=alert]')).toBeVisible();
    expect(await page.evaluate(() => window.cspViolations)).toEqual([]);
    expect(errors).toEqual([]);

    await page.evaluate(() => {
      const script = document.createElement('script');
      script.textContent = 'window.injectedScriptExecuted = true';
      document.body.append(script);
    });
    await expect.poll(() => page.evaluate(() => window.cspViolations)).toContain('script-src-elem');
    expect(await page.evaluate(() => window.injectedScriptExecuted)).toBeUndefined();
  });
}

test('the GitHub manifest POST is allowed by CSP and excludes the setup credential', async ({ page }) => {
  test.skip(!process.env.GRADEPUSH_TEST_SETUP_TOKEN, 'Requires the private token of the disposable setup instance.');
  let outgoing;
  await page.route('https://github.com/**', async route => {
    const request = route.request();
    const fields = new URLSearchParams(request.postData());
    outgoing = {
      method: request.method(),
      path: new URL(request.url()).pathname,
      fields: [...fields.keys()],
      manifest: JSON.parse(fields.get('manifest')),
      leaksCredential: request.postData().includes(process.env.GRADEPUSH_TEST_SETUP_TOKEN),
    };
    await route.fulfill({status: 200, contentType: 'text/html', body: '<h1>Intercepted GitHub form</h1>'});
  });
  await page.goto('/setup?locale=en');
  await expect(page.locator('.phx-connected')).toBeAttached();
  await page.locator('#setup_institution_name').fill('Security browser test');
  await page.locator('#setup_setup_token').fill(process.env.GRADEPUSH_TEST_SETUP_TOKEN);
  await page.locator('#setup-form button[type=submit]').click();
  await expect(page.getByRole('heading', {name: 'Intercepted GitHub form'})).toBeVisible();
  expect(outgoing.method).toBe('POST');
  expect(outgoing.path).toBe('/settings/apps/new');
  expect(outgoing.fields).toEqual(['manifest']);
  expect(outgoing.manifest.name).toBeTruthy();
  expect(outgoing.leaksCredential).toBe(false);
});
