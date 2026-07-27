/**
 * Infinite scroll for the admin media library browser (picker modals).
 *
 * The scroll root is the hook element itself (nested overflow-y-auto inside a
 * modal). Loads more when the footer nears the bottom of that container.
 * A short cooldown prevents duplicate requests while the LiveComponent patches;
 * updated() re-checks after each patch so continuous scrolling stays seamless.
 */
const COOLDOWN_MS = 400;
const PREFETCH_PX = 280;

let MediaLibraryBrowserInfiniteScroll = {
    mounted() {
        this.cooldownUntil = 0;
        this.rafId = null;
        this.timeoutId = null;
        this.onScroll = () => this.check();
        this.el.addEventListener("scroll", this.onScroll, { passive: true });
        this.resizeObserver = new ResizeObserver(() => this.check());
        this.resizeObserver.observe(this.el);
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
        this.el.removeEventListener("scroll", this.onScroll);
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

    footerId() {
        return this.el.dataset.loadMoreFooterId;
    },

    check() {
        if (!this.enabled() || Date.now() < this.cooldownUntil) {
            return;
        }

        const footerId = this.footerId();
        if (!footerId) {
            return;
        }

        const footer = document.getElementById(footerId);
        if (!footer) {
            return;
        }

        const containerRect = this.el.getBoundingClientRect();
        const footerRect = footer.getBoundingClientRect();
        const inZone = footerRect.top <= containerRect.bottom + PREFETCH_PX;

        if (!inZone) {
            return;
        }

        this.cooldownUntil = Date.now() + COOLDOWN_MS;
        // Target the owning LiveComponent (picker modal content uses phx-target).
        this.pushEventTo(this.el, "load-more-media", {});
    },
};

export default MediaLibraryBrowserInfiniteScroll;
