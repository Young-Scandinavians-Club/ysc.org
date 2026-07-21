const HIDE_DELAY_MS = 800;

/**
 * Reveals a styled scrollbar only while the user is interacting with a scroll container.
 * Pair with the `.thin-scrollbar` CSS class (hover also reveals the scrollbar on desktop).
 */
export default {
    mounted() {
        this.hideTimeout = null;

        this.show = () => {
            this.el.classList.add("is-interacting");
        };

        this.scheduleHide = () => {
            clearTimeout(this.hideTimeout);
            this.hideTimeout = setTimeout(() => {
                this.el.classList.remove("is-interacting");
            }, HIDE_DELAY_MS);
        };

        this.onScroll = () => {
            this.show();
            this.scheduleHide();
        };

        this.onPointerDown = () => {
            this.show();
        };

        this.onPointerUp = () => {
            this.scheduleHide();
        };

        this.el.addEventListener("scroll", this.onScroll, { passive: true });
        this.el.addEventListener("pointerdown", this.onPointerDown);
        this.el.addEventListener("pointerup", this.onPointerUp);
        this.el.addEventListener("pointercancel", this.onPointerUp);
    },

    destroyed() {
        clearTimeout(this.hideTimeout);
        this.el.removeEventListener("scroll", this.onScroll);
        this.el.removeEventListener("pointerdown", this.onPointerDown);
        this.el.removeEventListener("pointerup", this.onPointerUp);
        this.el.removeEventListener("pointercancel", this.onPointerUp);
    }
};
