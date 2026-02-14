# Sentry Loading Fix - Summary

## Problem
The Sentry bundle (`bundle.tracing.replay.min.js`) was being imported as an ES6 module in `app.js`, but esbuild wasn't properly bundling it, resulting in `window.Sentry` being undefined at runtime.

Error:
```
Uncaught TypeError: Cannot read properties of undefined (reading 'init')
```

## Root Cause
The Sentry bundle uses an IIFE (Immediately Invoked Function Expression) pattern that assigns to `window.Sentry`. When imported as an ES6 module, esbuild processes the import but doesn't execute the IIFE in a way that exposes the global variable.

## Solution
Load Sentry as a separate script tag **before** the main app.js bundle:

1. **Created Mix Task** (`lib/mix/tasks/copy_vendor_assets.ex`)
   - Copies `assets/vendor/bundle.tracing.replay.min.js` → `priv/static/assets/sentry.min.js`
   - Runs automatically during `mix assets.build` and `mix assets.deploy`

2. **Updated HTML Layouts**
   - `lib/ysc_web/components/layouts/root.html.heex`
   - `lib/ysc_web/components/layouts/admin_root.html.heex`
   - Added `<script src="/assets/sentry.min.js">` before `app.js`
   - Sentry loads synchronously (no defer) to ensure it's available
   - App.js loads with defer, but executes after Sentry

3. **Updated app.js**
   - Removed `import "../vendor/bundle.tracing.replay.min.js"`
   - Added debug logging to verify Sentry availability
   - Added retry mechanism with `waitForSentry()` function (5 attempts, 50ms delay)
   - All Sentry calls wrapped in safety checks

## Files Modified

### Created
- `lib/mix/tasks/copy_vendor_assets.ex` - Copy task for vendor assets

### Modified
- `assets/js/app.js` - Removed import, added safety checks and retry logic
- `lib/ysc_web/components/layouts/root.html.heex` - Added Sentry script tag
- `lib/ysc_web/components/layouts/admin_root.html.heex` - Added Sentry script tag
- `mix.exs` - Added `copy_vendor_assets` to build aliases

## Testing

1. **Verify the copy task works:**
   ```bash
   mix copy_vendor_assets
   ```
   Should output: "Copied Sentry bundle to .../priv/static/assets/sentry.min.js"

2. **Rebuild assets:**
   ```bash
   mix assets.build
   ```

3. **Start the dev server:**
   ```bash
   mix phx.server
   ```

4. **Check browser console:**
   - Look for: "After Sentry script tag, window.Sentry: ✓ Available"
   - Look for: "Sentry initialized successfully"
   - Should NOT see: "Sentry failed to load" or "window.Sentry: ✗ Undefined"

5. **Verify Sentry is working:**
   - Open browser DevTools → Console
   - Run: `window.Sentry`
   - Should see the Sentry object with methods like `init`, `captureException`, etc.

## Production Deployment

The `assets.deploy` alias already includes `copy_vendor_assets`, so production builds will automatically:
1. Copy the Sentry bundle
2. Minify assets
3. Run phx.digest to generate hashed filenames

The script tag uses Phoenix's `~p"/assets/sentry.min.js"` helper which will automatically use the hashed filename in production.

## Fallback Behavior

If Sentry still fails to load:
- The app will continue to function normally
- Console warnings will indicate Sentry is unavailable
- No errors will be thrown
- All Sentry calls are wrapped in `if (window.Sentry)` checks
