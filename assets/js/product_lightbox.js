// Full-screen viewer for the shop product gallery.
//
// The server owns which photo is current (`data-index`) and the list of slides
// (`data-slides`, JSON `[{href, alt}]`). Opening the viewer starts at the current
// photo; swiping inside it pushes `select_photo` so the page behind stays in sync.
import { loadScript, loadStylesheet } from "./load_external_asset";

const GLIGHTBOX_CSS = "https://unpkg.com/glightbox@3.3.1/dist/css/glightbox.min.css";
const GLIGHTBOX_JS = "https://unpkg.com/glightbox@3.3.1/dist/js/glightbox.min.js";

const ProductLightbox = {
    async mounted() {
        this.onClick = (e) => {
            if (!e.target.closest("[data-lightbox-open]")) return;
            e.preventDefault();
            this.open();
        };
        this.onKeydown = (e) => {
            if (e.key !== "Enter" && e.key !== " ") return;
            if (e.target.closest("[data-lightbox-open]") !== e.target) return;
            e.preventDefault();
            this.open();
        };
        this.el.addEventListener("click", this.onClick);
        this.el.addEventListener("keydown", this.onKeydown);

        loadStylesheet("glightbox-css", GLIGHTBOX_CSS);
        try {
            await loadScript("glightbox-js", GLIGHTBOX_JS);
        } catch (e) {
            console.error("GLightbox failed to load:", e);
        }
    },

    destroyed() {
        this.el.removeEventListener("click", this.onClick);
        this.el.removeEventListener("keydown", this.onKeydown);
        this.close();
    },

    slides() {
        try {
            const parsed = JSON.parse(this.el.dataset.slides || "[]");
            return parsed.filter((s) => safeHref(s.href)).map((s) => ({
                type: "image",
                href: s.href,
                alt: s.alt || "",
            }));
        } catch (_e) {
            return [];
        }
    },

    open() {
        if (typeof GLightbox === "undefined") return;
        const elements = this.slides();
        if (elements.length === 0) return;

        this.close();
        const start = Math.min(
            Math.max(parseInt(this.el.dataset.index || "0", 10) || 0, 0),
            elements.length - 1
        );

        // Reduced motion: no zoom or slide, the photo simply appears.
        const effect = window.matchMedia("(prefers-reduced-motion: reduce)").matches
            ? "none"
            : "fade";

        this.lightbox = GLightbox({
            elements,
            startAt: start,
            touchNavigation: true,
            keyboardNavigation: true,
            closeButton: true,
            loop: elements.length > 1,
            openEffect: effect,
            closeEffect: effect,
            slideEffect: effect === "none" ? "none" : "slide",
        });
        this.lightbox.on("slide_changed", ({ current }) => {
            if (current && typeof current.index === "number") {
                this.pushEvent("select_photo", { index: current.index });
            }
        });
        this.lightbox.on("close", () => {
            const trigger = this.el.querySelector("[data-lightbox-open]");
            if (trigger) trigger.focus({ preventScroll: true });
        });
        this.lightbox.open();
    },

    close() {
        if (this.lightbox) {
            this.lightbox.destroy();
            this.lightbox = null;
        }
    },
};

// Only web image URLs may reach the viewer (no javascript:, data:, etc.).
function safeHref(href) {
    if (typeof href !== "string") return false;
    if (href.startsWith("/") && !href.startsWith("//")) return true;
    try {
        const url = new URL(href, window.location.origin);
        return url.protocol === "https:" || url.protocol === "http:";
    } catch (_e) {
        return false;
    }
}

export default ProductLightbox;
