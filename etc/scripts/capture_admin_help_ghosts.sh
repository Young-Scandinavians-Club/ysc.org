#!/usr/bin/env bash
# Capture ghost preview pages as PNGs for print/PDF layouts.
# Requires: dev server on BASE_URL (default http://localhost:4000), npx + playwright.
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:4000}"
OUT_DIR="priv/static/images/admin-help"

if [[ -z "${ADMIN_EMAIL:-}" || -z "${ADMIN_PASSWORD:-}" ]]; then
  echo "ADMIN_EMAIL and ADMIN_PASSWORD must be set (no embedded defaults)." >&2
  exit 1
fi

EMAIL="$ADMIN_EMAIL"
PASSWORD="$ADMIN_PASSWORD"

mkdir -p "$OUT_DIR"

npx --yes playwright install chromium >/dev/null 2>&1 || true

BASE_URL="$BASE_URL" OUT_DIR="$OUT_DIR" ADMIN_EMAIL="$EMAIL" ADMIN_PASSWORD="$PASSWORD" node <<'NODE'
const { chromium } = require('playwright');

const baseUrl = process.env.BASE_URL || 'http://localhost:4000';
const outDir = process.env.OUT_DIR || 'priv/static/images/admin-help';
const email = process.env.ADMIN_EMAIL;
const password = process.env.ADMIN_PASSWORD;

if (!email || !password) {
  console.error('ADMIN_EMAIL and ADMIN_PASSWORD must be set (no embedded defaults).');
  process.exit(1);
}

const slugs = process.env.SLUGS ? process.env.SLUGS.split(',') : [
  'getting-started-dashboard','getting-started-sidebar','posts-list','posts-editor',
  'posts-settings','posts-publish','newsletter-compose','newsletter-subscribers',
  'events-list','events-edit','events-tickets','events-updates','media-gallery',
  'check-in-desk','scanner'
];

(async () => {
  const browser = await chromium.launch();
  const context = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  const page = await context.newPage();

  await page.goto(`${baseUrl}/users/log-in`);
  await page.fill('input[name="user[email]"]', email);
  await page.fill('input[name="user[password]"]', password);
  await page.click('button[type="submit"]');
  await page.waitForURL(/\/(admin|onboarding)/, { timeout: 15000 }).catch(() => {});

  for (const slug of slugs) {
    const url = `${baseUrl}/admin/help/ghost/${slug}?embed=1`;
    await page.goto(url, { waitUntil: 'networkidle' });
    await page.waitForSelector('.admin-help-ghost-embed, .admin-help-ghost-public', { timeout: 10000 });
    await page.screenshot({ path: `${outDir}/${slug}.png`, fullPage: false });
    console.log(`Wrote ${outDir}/${slug}.png`);
  }

  await browser.close();
})();
NODE
