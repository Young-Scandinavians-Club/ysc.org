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
        this.onScroll = () => this.check();
        window.addEventListener("scroll", this.onScroll, { passive: true });
        this.resizeObserver = new ResizeObserver(() => this.check());
        this.resizeObserver.observe(document.documentElement);
        requestAnimationFrame(() => this.check());
    },

    updated() {
        requestAnimationFrame(() => this.check());
        setTimeout(() => this.check(), COOLDOWN_MS + 50);
    },

    destroyed() {
        window.removeEventListener("scroll", this.onScroll);
        if (this.resizeObserver) {
            this.resizeObserver.disconnect();
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
