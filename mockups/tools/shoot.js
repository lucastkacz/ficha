// Renders a mock locally: CDN scripts come from the npm packages, kit files from disk.
// node mockups/tools/shoot.js <mockDir> <kitDir> <outDir> [dev], from the repo's folder (mockups/README.md)
const fs = require('fs');
const path = require('path');

const [mockDir, kitDir, outDir, dev] = process.argv.slice(2);
if (!mockDir || !kitDir || !outDir) {
  console.error('Usage: node mockups/tools/shoot.js <mockDir> <kitDir> <outDir> [dev], such as mockups/desktop mockups/kit /tmp/shots (mockups/README.md, "A debate\'s mock").');
  process.exit(2);
}
let chromium;
try {
  ({ chromium } = require('playwright'));
} catch (e) {
  console.error("Couldn't load Playwright, which shoot.js renders with. Run it in a Claude cloud session, which has it (mockups/README.md, \"A debate's mock\").");
  process.exit(1);
}
// The npm packages of React, ReactDOM and htm: NPMTEST, or npmtest/ beside tools/.
const npm = process.env.NPMTEST || path.join(__dirname, '..', 'npmtest');
const libs = {
  'react.production.min.js': path.join(npm, 'react-18.3.1/package/umd', dev ? 'react.development.js' : 'react.production.min.js'),
  'react-dom.production.min.js': path.join(npm, 'react-dom-18.3.1/package/umd', dev ? 'react-dom.development.js' : 'react-dom.production.min.js'),
  'htm.umd.js': path.join(npm, 'htm-3.1.1/package/dist/htm.umd.js'),
};
const missing = Object.values(libs).filter((f) => !fs.existsSync(f));
if (missing.length) {
  console.error(`Missing ${missing.join(', ')}: unpack React, ReactDOM and htm's npm packages into ${npm}, each in a folder named as its tarball (mockups/README.md, "A debate's mock", step 4).`);
  process.exit(1);
}
const fail = (what) => {
  console.error(`${what} (mockups/README.md, "A debate's mock", step 4).`);
  process.exit(1);
};
const json = (name, fallback) => {
  try {
    return JSON.parse(process.env[name] || fallback);
  } catch (e) {
    fail(`${name} isn't JSON: ${e.message}. Pass it as a JSON array`);
  }
};
const mockPage = path.join(mockDir, 'index.html');
if (!fs.existsSync(mockPage)) fail(`No ${mockPage}: pass the mock's folder, the one that holds its index.html, such as mockups/desktop`);
const page0 = fs.readFileSync(mockPage, 'utf8');
const wrapped = `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<style>:root{color-scheme:light}body{margin:0;font:14px system-ui}img{max-width:100%}[hidden]{display:none!important}</style></head><body>${page0}</body></html>`;

async function setup(browser, opts) {
  const ctx = await browser.newContext(opts);
  const page = await ctx.newPage();
  const errors = [];
  page.on('console', (m) => (m.type() === 'error' || m.type() === 'warning') && errors.push(`${m.type()}: ${m.text()}`));
  page.on('pageerror', (e) => errors.push(`pageerror: ${e.message}`));
  await page.route('**/*', (route) => {
    const url = route.request().url();
    const name = url.split('/').pop();
    if (libs[name]) return route.fulfill({ path: libs[name], contentType: 'application/javascript' });
    if (url.startsWith('http://mock.local/kit/')) return route.fulfill({ path: path.join(kitDir, url.slice('http://mock.local/kit/'.length)) });
    if (url === 'http://mock.local/') return route.fulfill({ body: wrapped, contentType: 'text/html' });
    return route.abort();
  });
  await page.goto('http://mock.local/');
  await page.waitForTimeout(600);
  return { ctx, page, errors };
}

(async () => {
  const steps = json('STEPS', '[]');
  const sizes = json('SIZES', '[{"name":"desk","width":1440,"height":860}]');
  const browser = await chromium.launch().catch((e) => fail(`Chromium didn't launch: ${e.message.split('\n')[0]}. Run shoot.js where Playwright's Chromium is installed, as in a Claude session in the cloud`));
  fs.mkdirSync(outDir, { recursive: true });
  for (const size of sizes) {
    const { ctx, page, errors } = await setup(browser, { viewport: { width: size.width, height: size.height }, colorScheme: size.dark ? 'dark' : 'light', deviceScaleFactor: 1 });
    await page.screenshot({ path: path.join(outDir, `${size.name}-0.png`), fullPage: !!size.full });
    let i = 1;
    for (const step of steps) {
      try {
        if (step.click) await page.getByText(step.click, { exact: step.exact ?? false }).first().click({ timeout: 5000 });
        if (step.css) await page.locator(step.css).first().click({ timeout: 5000 });
        if (step.select) await page.selectOption(step.select.css, step.select.value, { timeout: 5000 });
        if (step.key) await page.keyboard.press(step.key);
        if (step.hover) await page.locator(step.hover.css).nth(step.hover.nth || 0).hover({ position: { x: step.hover.x, y: step.hover.y }, timeout: 5000 });
      } catch (e) {
        await browser.close();
        fail(`At ${size.name}, the step ${JSON.stringify(step)} found nothing to act on: ${e.message.split('\n')[0].replace(/\.+$/, '')}. Check its text or selector against the mock, or take a shot just before it`);
      }
      if (step.wait) await page.waitForTimeout(step.wait);
      if (step.shot) await page.screenshot({ path: path.join(outDir, `${size.name}-${i++}-${step.shot}.png`), fullPage: !!size.full });
    }
    console.log(size.name, errors.length ? errors.join('\n') : 'no console errors');
    await ctx.close();
  }
  await browser.close();
})();
