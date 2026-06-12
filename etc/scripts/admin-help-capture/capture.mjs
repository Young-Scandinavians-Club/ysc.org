import { chromium } from "playwright";

const baseUrl = process.env.BASE_URL || "http://localhost:4000";
const outDir = process.env.OUT_DIR || "priv/static/images/admin-help";
const email = process.env.ADMIN_EMAIL;
const password = process.env.ADMIN_PASSWORD;
const targets = JSON.parse(process.env.TARGETS_JSON || "[]");

if (!email || !password) {
  console.error(
    "ADMIN_EMAIL and ADMIN_PASSWORD must be set (no embedded defaults)."
  );
  process.exit(1);
}

function assetBasename(slug, scrollTo) {
  if (scrollTo) return `${slug}--${scrollTo}`;
  return slug;
}

function ghostUrl(slug, scrollTo) {
  const params = new URLSearchParams({ embed: "1" });
  if (scrollTo) params.set("scroll_to", scrollTo);
  return `${baseUrl}/admin/help/ghost/${slug}?${params.toString()}`;
}

async function waitForGhostReady(page) {
  await page.waitForSelector("#admin-help-ghost-root", { timeout: 20000 });
  await page.waitForSelector(
    ".admin-help-ghost-embed, .admin-help-ghost-public",
    { timeout: 20000 }
  );
  await page.waitForTimeout(600);
}

async function captureTarget(page, { slug, scroll_to: scrollTo }, outDir) {
  const basename = assetBasename(slug, scrollTo);
  const outPath = `${outDir}/${basename}.png`;
  const url = ghostUrl(slug, scrollTo);

  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      await page.goto(url, { waitUntil: "load", timeout: 30000 });
      await waitForGhostReady(page);
      await page.locator("#admin-help-ghost-root").screenshot({ path: outPath });
      console.log(`Wrote ${outPath}`);
      return;
    } catch (error) {
      if (attempt === 3) throw error;
      console.warn(`Retry ${attempt}/3 for ${basename}: ${error.message}`);
      await page.waitForTimeout(1000);
    }
  }
}

const browser = await chromium.launch();
const context = await browser.newContext({
  viewport: { width: 1280, height: 800 },
});
const page = await context.newPage();

await page.goto(`${baseUrl}/users/log-in`, { waitUntil: "networkidle" });
await page.locator("#login_form input[name='user[email]']").fill(email);
await page.locator("#login_form input[name='user[password]']").fill(password);
await page.getByRole("button", { name: "Sign in", exact: true }).click();
await page
  .waitForURL(/\/(admin|onboarding)/, { timeout: 15000 })
  .catch(() => {});

for (const target of targets) {
  await captureTarget(page, target, outDir);
}

await browser.close();
