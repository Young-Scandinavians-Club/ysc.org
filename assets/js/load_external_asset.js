// Idempotently injects external <script> or <link> tags into <head>.
// Safe to call multiple times — uses the `id` to prevent duplicate injection.
//
// Scripts: trusted via CSP 'strict-dynamic' — scripts injected by the nonce-approved
// app.js bundle are automatically allowed by the browser regardless of origin.
//
// Stylesheets: trusted via explicit host allowlist in style-src CSP directive.

export function loadScript(id, src) {
    if (document.getElementById(id)) return;
    const script = document.createElement("script");
    script.id = id;
    script.src = src;
    script.defer = true;
    document.head.appendChild(script);
}

export function loadStylesheet(id, href) {
    if (document.getElementById(id)) return;
    const link = document.createElement("link");
    link.id = id;
    link.rel = "stylesheet";
    link.href = href;
    document.head.appendChild(link);
}
