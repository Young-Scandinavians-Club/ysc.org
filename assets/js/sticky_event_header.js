// Adds/removes the `is-sticky` CSS class on the event header bar
// when it transitions into/out of its sticky position.
// A zero-height sentinel div inserted just before the element is observed;
// when the sentinel scrolls out of view the header is sticky.
//
// Also publishes --event-header-height as a CSS custom property on <html>
// while sticky so that other sticky elements (e.g. the Trix toolbar) can
// offset themselves by the correct amount.
export default StickyEventHeader = {
    mounted() {
        this.sticky = false;

        this.sentinel = document.createElement("div");
        this.sentinel.setAttribute("aria-hidden", "true");
        this.sentinel.style.cssText = "height:1px;margin-top:-1px;pointer-events:none";
        this.el.parentElement.insertBefore(this.sentinel, this.el);

        this.observer = new IntersectionObserver(
            ([entry]) => {
                this.sticky = !entry.isIntersecting;
                this.el.classList.toggle("is-sticky", this.sticky);
                this.updateHeightVar();
            },
            { threshold: [1] }
        );

        this.observer.observe(this.sentinel);
    },

    // LiveView patches wipe client-added classes; restore `is-sticky` if needed.
    updated() {
        if (this.sticky && !this.el.classList.contains("is-sticky")) {
            this.el.classList.add("is-sticky");
        }
        // Re-measure in case the header height changed due to a content update.
        this.updateHeightVar();
    },

    destroyed() {
        if (this.observer) this.observer.disconnect();
        if (this.sentinel && this.sentinel.parentElement) {
            this.sentinel.parentElement.removeChild(this.sentinel);
        }
        document.documentElement.style.removeProperty("--event-header-height");
    },

    updateHeightVar() {
        if (this.sticky) {
            // Defer one frame so the collapsed styles are applied before measuring.
            requestAnimationFrame(() => {
                const h = this.el.getBoundingClientRect().height;
                document.documentElement.style.setProperty("--event-header-height", h + "px");
            });
        } else {
            document.documentElement.style.removeProperty("--event-header-height");
        }
    },
};
