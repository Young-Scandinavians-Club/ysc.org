/**
 * AutoResizeIframe — sizes an iframe to fit its srcdoc content and prints it.
 *
 * Works with `phx-update="ignore"` so LiveView does not re-render it.
 * Waits for all images to load before taking the final height measurement.
 *
 * The iframe must be sandboxed with `allow-same-origin` (so we can read its
 * document) and `allow-modals` (so Chrome lets us call print() in it). It must
 * NOT get `allow-scripts`: that combination would let the archived email escape
 * the sandbox.
 */

// Print rules injected into the archived email. The archive is MJML output, and
// stored editions predate any template change, so this is applied client-side.
//
// MJML wraps every column in `display: inline-block`. Chrome treats inline-blocks
// as unbreakable when paginating, so long text and tall images get clipped or
// pushed whole onto the next page. Making them blocks lets content flow normally.
const PRINT_CSS = `
@page { margin: 14mm 12mm; }
@media print {
  * { -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; }
  html, body, body > div { background: #fff !important; }
  div[class*="mj-column-per-"], .mj-outlook-group-fix { display: block !important; }
  div[style*="max-width:600px"] { break-inside: avoid; }
  a[href*="unsubscribe"] { display: none !important; }
  img { max-width: 100% !important; break-inside: avoid; break-after: avoid; }
  p { orphans: 3; widows: 3; }
  h1, h2, h3, h4 { break-after: avoid; }
}`;

function waitForImages(doc) {
    const pending = Array.from(doc.getElementsByTagName("img")).filter(
        (img) => !img.complete
    );
    if (pending.length === 0) return Promise.resolve();
    return Promise.all(
        pending.map(
            (img) =>
                new Promise((resolve) => {
                    img.addEventListener("load", resolve, { once: true });
                    img.addEventListener("error", resolve, { once: true });
                })
        )
    );
}

function resizeIframe(el) {
    try {
        const doc = el.contentDocument || el.contentWindow.document;
        if (!doc || !doc.body) return;
        const height = Math.max(doc.body.scrollHeight, doc.body.offsetHeight);
        if (height > 0) el.style.height = `${height}px`;
    } catch (_e) {}
}

function ensurePrintStyles(doc) {
    if (doc.getElementById("newsletter-print-css")) return;
    const style = doc.createElement("style");
    style.id = "newsletter-print-css";
    style.textContent = PRINT_CSS;
    doc.head.appendChild(style);
}

const AutoResizeIframe = {
    async mounted() {
        const el = this.el;

        const doResize = async () => {
            resizeIframe(el);
            try {
                const doc = el.contentDocument || el.contentWindow.document;
                await waitForImages(doc);
            } catch (_e) {}
            resizeIframe(el);
        };

        if (el.contentDocument && el.contentDocument.readyState === "complete") {
            doResize();
        } else {
            el.addEventListener("load", doResize, { once: true });
        }

        el.addEventListener("newsletter:print", async () => {
            const win = el.contentWindow;
            const doc = el.contentDocument;
            if (!win || !doc || !doc.head) return;

            ensurePrintStyles(doc);
            await waitForImages(doc);
            win.focus();
            win.print();
        });
    },
};

export default AutoResizeIframe;
