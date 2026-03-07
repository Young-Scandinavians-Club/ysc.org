// Idempotently injects external <script> or <link> tags into <head>.
// Returns a Promise for scripts so callers can await actual load completion.
//
// Scripts: trusted via CSP 'strict-dynamic' — scripts injected by the nonce-approved
// app.js bundle are automatically allowed by the browser regardless of origin.
//
// Stylesheets: trusted via explicit host allowlist in style-src CSP directive.

// Tracks in-flight and completed script loads so concurrent hooks share the same Promise.
const scriptPromises = {};

export function loadScript(id, src) {
    if (scriptPromises[id]) return scriptPromises[id];

    scriptPromises[id] = new Promise((resolve, reject) => {
        const existing = document.getElementById(id);
        if (existing) {
            // Tag already in DOM from a previous page load — library is ready.
            resolve();
            return;
        }

        const script = document.createElement("script");
        script.id = id;
        script.src = src;
        script.async = true;
        script.onload = resolve;
        script.onerror = (e) => {
            delete scriptPromises[id];
            reject(e);
        };
        document.head.appendChild(script);
    });

    return scriptPromises[id];
}

export function loadStylesheet(id, href) {
    if (document.getElementById(id)) return;
    const link = document.createElement("link");
    link.id = id;
    link.rel = "stylesheet";
    link.href = href;
    document.head.appendChild(link);
}
