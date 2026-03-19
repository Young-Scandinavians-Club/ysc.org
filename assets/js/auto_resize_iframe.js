/**
 * AutoResizeIframe — sizes an iframe to fit its srcdoc content.
 *
 * Works with `phx-update="ignore"` so LiveView does not re-render it.
 * Waits for all images to load before taking the final height measurement.
 */

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

        el.addEventListener("newsletter:print", () => {
            try {
                const doc = el.contentDocument || el.contentWindow.document;
                let html = doc.documentElement.outerHTML;

                // Ensure relative image/asset URLs resolve correctly when the
                // document is opened standalone via a blob URL.
                const baseTag = `<base href="${window.location.origin}">`;
                html = html.replace(/<head>/i, "<head>" + baseTag);

                // Preserve background colours and images in print output.
                const printCss = `<style>
@media print {
  * { -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; }
}
</style>`;
                html = html.replace(/<\/head>/i, printCss + "</head>");

                const blob = new Blob([html], { type: "text/html" });
                const url = URL.createObjectURL(blob);
                const win = window.open(url);
                if (win) {
                    win.addEventListener(
                        "load",
                        () => {
                            // Small delay lets the browser finish applying styles.
                            setTimeout(() => {
                                win.print();
                                URL.revokeObjectURL(url);
                            }, 400);
                        },
                        { once: true }
                    );
                }
            } catch (_e) {}
        });
    },
};

export default AutoResizeIframe;
