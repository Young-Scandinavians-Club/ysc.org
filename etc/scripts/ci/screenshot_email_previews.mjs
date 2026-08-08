#!/usr/bin/env node
/**
 * Screenshot email HTML files in a directory to PNG using Playwright.
 *
 * Usage: node screenshot_email_previews.mjs <previews_dir>
 *
 * Resolves playwright from PLAYWRIGHT_NODE_PATH / NODE_PATH when set (CI installs
 * the package outside the repo). Plain `import "playwright"` does not honor
 * NODE_PATH under ES modules.
 */
import fs from "fs";
import path from "path";
import { pathToFileURL } from "url";

async function importPlaywright() {
  const roots = [process.env.PLAYWRIGHT_NODE_PATH, process.env.NODE_PATH]
    .filter(Boolean)
    .flatMap((p) => String(p).split(path.delimiter));

  for (const root of roots) {
    // Prefer the package's ESM entry (index.mjs); index.js is CJS-only.
    for (const file of ["index.mjs", "index.js"]) {
      const entry = path.join(root, "playwright", file);
      if (fs.existsSync(entry)) {
        return import(pathToFileURL(entry).href);
      }
    }
  }

  return import("playwright");
}

async function main() {
  const dir = process.argv[2];
  if (!dir) {
    console.error("Usage: screenshot_email_previews.mjs <previews_dir>");
    process.exit(1);
  }

  const absDir = path.resolve(dir);
  const htmlFiles = fs
    .readdirSync(absDir)
    .filter((f) => f.endsWith(".html"))
    .sort();

  if (htmlFiles.length === 0) {
    console.error(`No HTML files in ${absDir}`);
    process.exit(1);
  }

  const { chromium } = await importPlaywright();
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: { width: 680, height: 900 },
    deviceScaleFactor: 2,
  });

  for (const file of htmlFiles) {
    const htmlPath = path.join(absDir, file);
    const pngPath = path.join(absDir, file.replace(/\.html$/, ".png"));
    const page = await context.newPage();
    await page.goto(pathToFileURL(htmlPath).href, {
      waitUntil: "networkidle",
    });
    // Emails are typically ~600px wide; full-page capture for long templates.
    await page.screenshot({ path: pngPath, fullPage: true, type: "png" });
    await page.close();
    console.log(`screenshot ${file} -> ${path.basename(pngPath)}`);
  }

  await browser.close();
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
