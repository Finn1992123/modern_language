const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const baseUrl = 'http://localhost:5200';
const outDir = path.join('store_assets', 'screenshots');

const devices = [
  { name: 'phone', width: 390, height: 844 },
  { name: 'tablet7', width: 1080, height: 1920 },
  { name: 'tablet10', width: 1200, height: 1920 },
];

function shotPath(device, index, title) {
  return path.join(outDir, `${device}_${String(index).padStart(2, '0')}_${title}.png`);
}

async function login(page, width, height) {
  await page.goto(baseUrl, { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(2500);

  await page.mouse.click(width * 0.5, height * 0.477);
  await page.keyboard.type('parent-review@modernlanguage.gr');
  await page.waitForTimeout(250);
  await page.mouse.click(width * 0.5, height * 0.553);
  await page.keyboard.type('parentreview');
  await page.waitForTimeout(250);
  await page.mouse.click(width * 0.5, height * 0.637);
  await page.waitForTimeout(7000);
}

async function captureLoggedInSet(browser) {
  const phone = devices[0];
  const context = await browser.newContext({
    viewport: { width: phone.width, height: phone.height },
    deviceScaleFactor: 1,
  });
  const page = await context.newPage();

  await page.goto(baseUrl, { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(3000);
  await page.screenshot({ path: shotPath('phone', 1, 'login') });

  await login(page, phone.width, phone.height);
  await page.screenshot({ path: shotPath('phone', 2, 'home') });

  await page.mouse.click(phone.width - 48, 48);
  await page.waitForTimeout(1500);
  await page.screenshot({ path: shotPath('phone', 3, 'profile') });

  for (const device of devices.slice(1)) {
    await page.setViewportSize({ width: device.width, height: device.height });
    await page.goto(baseUrl, { waitUntil: 'networkidle', timeout: 60000 });
    await page.waitForTimeout(2500);
    await page.screenshot({ path: shotPath(device.name, 1, 'home') });

    await page.mouse.click(device.width - 48, 48);
    await page.waitForTimeout(1500);
    await page.screenshot({ path: shotPath(device.name, 2, 'profile') });
  }

  await context.close();
}

async function main() {
  fs.mkdirSync(outDir, { recursive: true });
  const browser = await chromium.launch({ channel: 'chrome', headless: true });
  await captureLoggedInSet(browser);
  await browser.close();
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
