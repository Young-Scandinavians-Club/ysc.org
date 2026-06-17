/**
 * Infinite scroll for the admin media gallery.
 *
 * Loads more when the footer nears the viewport. A short cooldown prevents
 * duplicate requests while the server responds; updated() re-checks after each
 * patch so continuous scrolling stays seamless (no scroll-up-and-back-down).
 */
const COOLDOWN_MS = 400;
const PREFETCH_PX = 280;

let MediaGalleryInfiniteScroll = {
    mounted() {
        this.cooldownUntil = 0;
        this.rafId = null;
        this.timeoutId = null;
        this.onScroll = () => this.check();
        window.addEventListener("scroll", this.onScroll, { passive: true });
        this.resizeObserver = new ResizeObserver(() => this.check());
        this.resizeObserver.observe(document.documentElement);
        this.rafId = requestAnimationFrame(() => {
            this.rafId = null;
            this.check();
        });
    },

    updated() {
        this.clearScheduledChecks();
        this.rafId = requestAnimationFrame(() => {
            this.rafId = null;
            this.check();
        });
        this.timeoutId = setTimeout(() => {
            this.timeoutId = null;
            this.check();
        }, COOLDOWN_MS + 50);
    },

    destroyed() {
        this.clearScheduledChecks();
        window.removeEventListener("scroll", this.onScroll);
        if (this.resizeObserver) {
            this.resizeObserver.disconnect();
        }
    },

    clearScheduledChecks() {
        if (this.rafId != null) {
            cancelAnimationFrame(this.rafId);
            this.rafId = null;
        }

        if (this.timeoutId != null) {
            clearTimeout(this.timeoutId);
            this.timeoutId = null;
        }
    },

    enabled() {
        return this.el.dataset.loadMoreEnabled === "true";
    },

    check() {
        if (!this.enabled() || Date.now() < this.cooldownUntil) {
            return;
        }

        const footer = document.getElementById("media-load-more-footer");
        if (!footer) {
            return;
        }

        const rect = footer.getBoundingClientRect();
        const inZone = rect.top <= window.innerHeight + PREFETCH_PX;

        if (!inZone) {
            return;
        }

        this.cooldownUntil = Date.now() + COOLDOWN_MS;
        this.pushEvent("load-more", {});
    },
};

export default MediaGalleryInfiniteScroll;
