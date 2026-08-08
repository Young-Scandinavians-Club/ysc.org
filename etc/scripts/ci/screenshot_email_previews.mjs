#!/usr/bin/env node
/**
 * Screenshot email HTML files in a directory to PNG using Playwright.
 *
 * Usage: node screenshot_email_previews.mjs <previews_dir>
 *
 * Resolves playwright from PLAYWRIGHT_NODE_PATH / NODE_PATH when set (CI installs
 * the package outside the repo). Plain `import "playwright"` does not honor
 * NODE_PATH under ES modules.
 *
 * Email HTML references static assets via absolute URLs (Endpoint.url() +
 * "/images/..."). There is no Phoenix server in this job, so localhost
 * requests are fulfilled from priv/static.
 */
import fs from "fs";
import path from "path";
import { fileURLToPath, pathToFileURL } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

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

function resolveStaticRoot() {
  if (process.env.STATIC_ROOT) {
    return path.resolve(process.env.STATIC_ROOT);
  }

  const repoRoot = process.env.YSC_REPO_ROOT
    ? path.resolve(process.env.YSC_REPO_ROOT)
    : path.resolve(__dirname, "../../..");

  return path.join(repoRoot, "priv/static");
}

function contentTypeFor(filePath) {
  switch (path.extname(filePath).toLowerCase()) {
    case ".png":
      return "image/png";
    case ".jpg":
    case ".jpeg":
      return "image/jpeg";
    case ".gif":
      return "image/gif";
    case ".webp":
      return "image/webp";
    case ".svg":
      return "image/svg+xml";
    case ".css":
      return "text/css";
    default:
      return "application/octet-stream";
  }
}

/**
 * Map http(s)://localhost[:port]/path to priv/static/path when the file exists.
 * Aborts other localhost requests so screenshots do not hang waiting on a
 * non-running Phoenix server.
 */
async function installStaticAssetRoute(context, staticRoot) {
  const root = path.resolve(staticRoot);
  if (!fs.existsSync(root)) {
    console.warn(`STATIC_ROOT does not exist: ${root}`);
    return;
  }

  await context.route(/https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?\/.*/, async (route) => {
    const url = new URL(route.request().url());
    const pathname = decodeURIComponent(url.pathname);
    const candidate = path.resolve(root, "." + pathname);

    if (
      (candidate === root || candidate.startsWith(root + path.sep)) &&
      fs.existsSync(candidate) &&
      fs.statSync(candidate).isFile()
    ) {
      await route.fulfill({
        status: 200,
        contentType: contentTypeFor(candidate),
        body: fs.readFileSync(candidate),
      });
      return;
    }

    await route.abort();
  });
}

async function waitForImages(page) {
  await page.evaluate(async () => {
    const images = Array.from(document.images);
    await Promise.all(
      images.map((img) => {
        if (img.complete) return Promise.resolve();
        return new Promise((resolve) => {
          img.addEventListener("load", resolve, { once: true });
          img.addEventListener("error", resolve, { once: true });
        });
      }),
    );
  });
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

  const staticRoot = resolveStaticRoot();
  console.log(`serving static assets from ${staticRoot}`);

  const { chromium } = await importPlaywright();
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: { width: 680, height: 900 },
    deviceScaleFactor: 2,
  });
  await installStaticAssetRoute(context, staticRoot);

  for (const file of htmlFiles) {
    const htmlPath = path.join(absDir, file);
    const pngPath = path.join(absDir, file.replace(/\.html$/, ".png"));
    const page = await context.newPage();
    await page.goto(pathToFileURL(htmlPath).href, {
      waitUntil: "networkidle",
    });
    await waitForImages(page);
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
