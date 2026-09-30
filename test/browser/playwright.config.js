import { defineConfig } from '@playwright/test';

const origin = new URL(process.env.GRADEPUSH_TEST_URL || 'https://localhost:4000');
const local = ['localhost', 'grades.example'].includes(origin.hostname);
const deployed = process.env.GRADEPUSH_DEPLOYED_TESTS === 'true' &&
  ['demo.gradepush.ca', 'test.gradepush.ca'].includes(origin.hostname);
if (origin.protocol !== 'https:' || (!local && !deployed)) {
  throw new Error('Use local HTTPS or explicitly enable tests on the designated demo/test deployments.');
}

export default defineConfig({
  testDir: '.',
  testMatch: process.env.GRADEPUSH_TEST_MODE === 'demo' ? 'demo.spec.js' : 'security.spec.js',
  workers: 1,
  forbidOnly: Boolean(process.env.CI),
  retries: 0,
  timeout: 30000,
  reporter: 'list',
  use: {
    baseURL: origin.origin,
    browserName: 'chromium',
    ignoreHTTPSErrors: local,
    launchOptions: {args: local ? ['--host-resolver-rules=MAP grades.example 127.0.0.1'] : []},
    trace: 'off',
    screenshot: 'off',
    video: 'off',
  },
});
