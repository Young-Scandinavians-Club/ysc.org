// Full-screen viewer for the shop product gallery.
//
// The server owns which photo is current (`data-index`) and the list of slides
// (`data-slides`, JSON `[{href, alt}]`). Opening the viewer starts at the current
// photo; swiping inside it pushes `select_photo` so the page behind stays in sync.
//
// Swiping the main photo on a touch screen steps to the previous / next photo, and
// the thumbnail strip follows so the current thumbnail stays in view.
import { loadScript, loadStylesheet } from "./load_external_asset";

const GLIGHTBOX_CSS = "https://unpkg.com/glightbox@3.3.1/dist/css/glightbox.min.css";
const GLIGHTBOX_JS = "https://unpkg.com/glightbox@3.3.1/dist/js/glightbox.min.js";

// A horizontal drag counts as a swipe past this distance, and only when it is
// clearly more horizontal than vertical.
const SWIPE_MIN_PX = 40;
const SWIPE_AXIS_RATIO = 1.5;

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

        this.swipe = null;
        this.suppressClick = false;
        this.onPointerDown = (e) => {
            if (e.pointerType === "mouse" || !e.isPrimary) return;
            if (!e.target.closest("[data-photo-swipe]")) return;
            this.swipe = { id: e.pointerId, x: e.clientX, y: e.clientY };
            // Listen on the document so a pen lifted outside the gallery still ends the swipe.
            document.addEventListener("pointerup", this.onPointerUp);
            document.addEventListener("pointercancel", this.onPointerCancel);
        };
        this.endSwipe = () => {
            this.swipe = null;
            document.removeEventListener("pointerup", this.onPointerUp);
            document.removeEventListener("pointercancel", this.onPointerCancel);
        };
        this.onPointerUp = (e) => {
            const start = this.swipe;
            if (!start || start.id !== e.pointerId) return;
            this.endSwipe();

            const dx = e.clientX - start.x;
            const dy = e.clientY - start.y;
            if (Math.abs(dx) < SWIPE_MIN_PX) return;
            if (Math.abs(dx) < Math.abs(dy) * SWIPE_AXIS_RATIO) return;

            // The click that follows a swipe must not open the full-screen viewer.
            this.suppressClick = true;
            setTimeout(() => (this.suppressClick = false), 0);
            this.pushEvent(dx < 0 ? "next_photo" : "prev_photo", {});
        };
        this.onPointerCancel = (e) => {
            if (this.swipe && this.swipe.id === e.pointerId) this.endSwipe();
        };
        this.onClickCapture = (e) => {
            if (!this.suppressClick) return;
            e.preventDefault();
            e.stopPropagation();
        };
        this.el.addEventListener("pointerdown", this.onPointerDown);
        this.el.addEventListener("click", this.onClickCapture, true);
        this.lastReveal = this.revealKey();

        loadStylesheet("glightbox-css", GLIGHTBOX_CSS);
        try {
            await loadScript("glightbox-js", GLIGHTBOX_JS);
        } catch (e) {
            console.error("GLightbox failed to load:", e);
        }
    },

    updated() {
        // Re-reveal when the photo or the photo set changes (e.g. a new colour at index 0).
        const key = this.revealKey();
        if (key === this.lastReveal) return;
        this.lastReveal = key;
        this.revealCurrentThumb();
    },

    revealKey() {
        return `${this.el.dataset.index}|${this.el.dataset.slides}`;
    },

    // Scroll the thumbnail strip (not the page) so the current thumbnail is visible.
    revealCurrentThumb() {
        const strip = this.el.querySelector("#photo-thumbs");
        const thumb = strip && strip.querySelector('[aria-current="true"]');
        if (!thumb) return;

        const stripBox = strip.getBoundingClientRect();
        const thumbBox = thumb.getBoundingClientRect();
        const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
        let delta = 0;
        if (thumbBox.left < stripBox.left) delta = thumbBox.left - stripBox.left;
        else if (thumbBox.right > stripBox.right) delta = thumbBox.right - stripBox.right;
        if (delta !== 0) {
            strip.scrollBy({ left: delta, behavior: reduced ? "auto" : "smooth" });
        } else {
            // Already visible: stop any smooth scroll from an earlier selection.
            strip.scrollTo({ left: strip.scrollLeft, behavior: "auto" });
        }
    },

    destroyed() {
        this.el.removeEventListener("pointerdown", this.onPointerDown);
        this.endSwipe();
        this.el.removeEventListener("click", this.onClickCapture, true);
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
