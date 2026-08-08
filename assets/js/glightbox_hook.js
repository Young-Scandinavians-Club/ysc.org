// GLightbox Hook for Trix images and inline image links in Phoenix LiveView
import { loadScript, loadStylesheet } from "./load_external_asset";

const IMAGE_EXTENSIONS = /\.(jpe?g|png|gif|webp|avif|svg)(\?|$)/i;

const GLightboxHook = {
    async mounted() {
        this._glightboxReady = false;
        loadStylesheet("glightbox-css", "https://unpkg.com/glightbox@3.3.1/dist/css/glightbox.min.css");
        try {
            await loadScript("glightbox-js", "https://unpkg.com/glightbox@3.3.1/dist/js/glightbox.min.js");
            this._glightboxReady = true;
            this.initializeLightbox();
        } catch (e) {
            console.error("GLightbox failed to load:", e);
        }
    },

    updated() {
        if (!this._glightboxReady || typeof GLightbox === "undefined") return;
        this.initializeLightbox();
    },

    initializeLightbox() {
        if (typeof GLightbox === "undefined") return;

        // Collect lightbox-ready elements from both Trix figures and plain image links
        const elements = [];
        const clickTargets = [];

        // 1) Trix figures: figure.attachment[data-trix-attachment] with an <img>
        //    Some attachments are wrapped in <a href>, others are bare <img> only
        //    (common when Trix attachment JSON has url but no href).
        this.el.querySelectorAll("figure.attachment[data-trix-attachment]").forEach((fig) => {
            const img = fig.querySelector("img");
            if (!img) return;

            const link = fig.querySelector("a[href]");
            const href = cleanImageHref(
                (link && link.getAttribute("href")) ||
                    img.getAttribute("src") ||
                    attachmentUrl(fig)
            );
            if (!href) return;

            const cap = fig.querySelector("figcaption")?.textContent?.trim() || "";
            const entry = { href, type: "image" };
            if (cap) entry.title = cap;

            elements.push(entry);
            const target = link || img;
            target.classList.add("glightbox");
            if (!link) {
                target.style.cursor = "zoom-in";
            }
            clickTargets.push(target);
        });

        // 2) Plain inline image links: a[href] > img (not inside a Trix figure)
        this.el.querySelectorAll("a[href]").forEach((link) => {
            const img = link.querySelector("img");
            if (!img) return;
            if (link.closest("figure.attachment[data-trix-attachment]")) return;
            if (link.dataset.glightboxReady) return;

            const href = link.getAttribute("href");
            const src = img.getAttribute("src");
            if (!IMAGE_EXTENSIONS.test(href) && !IMAGE_EXTENSIONS.test(src)) return;

            // Extract caption text from siblings of the img inside the link
            const caption = extractCaption(link, img);

            // Restructure DOM for nicer presentation
            restructureImageLink(link, img, caption);

            // Clean URL (strip download disposition) for both the link and lightbox
            const cleanHref = cleanImageHref(href);
            link.setAttribute("href", cleanHref);
            link.classList.add("glightbox");

            const entry = { href: cleanHref, type: "image" };
            if (caption) entry.title = caption;

            elements.push(entry);
            clickTargets.push(link);

            link.dataset.glightboxReady = "true";
        });

        if (elements.length === 0) return;

        // Tear down previous instance
        if (this.lightboxInstance) {
            this.lightboxInstance.destroy();
        }

        // Build a single GLightbox with the collected elements
        this.lightboxInstance = GLightbox({
            elements: elements,
            touchNavigation: true,
            closeButton: true,
            openEffect: "fade",
            closeEffect: "fade",
        });

        // Bind click handlers so each image opens the lightbox at its index
        const lb = this.lightboxInstance;
        clickTargets.forEach((target, index) => {
            // Remove old handler if re-initializing
            if (target._glightboxHandler) {
                target.removeEventListener("click", target._glightboxHandler);
            }
            const handler = (e) => {
                e.preventDefault();
                e.stopPropagation();
                lb.openAt(index);
            };
            target._glightboxHandler = handler;
            target.addEventListener("click", handler);
        });
    },

    destroyed() {
        if (this.lightboxInstance) {
            this.lightboxInstance.destroy();
            this.lightboxInstance = null;
        }
    },
};

function cleanImageHref(href) {
    if (!href) return "";
    try {
        const url = new URL(href, window.location.origin);
        url.searchParams.delete("content-disposition");
        // Keep absolute URLs absolute; relative ones relative
        if (/^https?:\/\//i.test(href)) return url.toString();
        return `${url.pathname}${url.search}${url.hash}`;
    } catch (_) {
        return href
            .replace(/([?&])content-disposition=[^&]*/gi, "$1")
            .replace(/\?&/, "?")
            .replace(/[?&]$/, "");
    }
}

function attachmentUrl(fig) {
    const raw = fig.getAttribute("data-trix-attachment");
    if (!raw) return null;
    try {
        const meta = JSON.parse(raw.replace(/&quot;/g, '"'));
        return meta.url || meta.href || null;
    } catch (_) {
        return null;
    }
}

function extractCaption(link, img) {
    let caption = "";
    for (const node of link.childNodes) {
        if (node === img) continue;
        if (node.nodeType === Node.TEXT_NODE) {
            caption += node.textContent;
        } else if (node.nodeType === Node.ELEMENT_NODE && node.tagName !== "IMG") {
            caption += node.textContent;
        }
    }
    return caption.trim();
}

function restructureImageLink(link, img, caption) {
    // Remove all child nodes that aren't the img (text captions, etc.)
    const toRemove = [];
    for (const node of link.childNodes) {
        if (node !== img) toRemove.push(node);
    }
    toRemove.forEach((n) => n.remove());

    // Wrap the link in a figure-like container
    const wrapper = document.createElement("figure");
    wrapper.className = "post-render-image-figure";
    link.parentNode.insertBefore(wrapper, link);
    wrapper.appendChild(link);

    // Add styled caption below the image if present
    if (caption) {
        const captionEl = document.createElement("figcaption");
        captionEl.className = "post-render-caption";
        captionEl.textContent = caption;
        wrapper.appendChild(captionEl);
    }
}

module.exports = GLightboxHook;
