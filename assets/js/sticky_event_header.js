// Adds/removes the `is-sticky` CSS class on the event header bar
// when it transitions into/out of its sticky position.
// A thin sentinel div inserted just before the element is observed; when the
// sentinel leaves the viewport (user scrolled down) the header is sticky.
//
// Use threshold 0, not 1: a 1px target with threshold [1] often fails the
// "fully visible" check on first paint (subpixel/layout), so the header looked
// collapsed immediately even at scroll 0.
//
// Also publishes --event-header-height as a CSS custom property on <html>
// while sticky so that other sticky elements (e.g. the Trix toolbar) can
// offset themselves by the correct amount.
//
// The header height animates when `is-sticky` toggles (CSS transitions). A
// single rAF measure captured the *expanded* height while the bar visually
// collapsed, so --event-header-height was too large and the Trix toolbar sat
// far below the header. ResizeObserver keeps the variable in sync with the
// real layout height until transitions settle.
const StickyEventHeader = {
    mounted() {
        this.sticky = false;

        this.sentinel = document.createElement("div");
        this.sentinel.setAttribute("aria-hidden", "true");
        this.sentinel.style.cssText =
            "height:2px;margin-top:-2px;pointer-events:none;flex-shrink:0";
        this.el.parentElement.insertBefore(this.sentinel, this.el);

        this.resizeObserver = new ResizeObserver(() => {
            this.syncEventHeaderHeightVar();
        });

        this.applySticky = (sticky) => {
            if (sticky === this.sticky) return;
            this.sticky = sticky;
            this.el.classList.toggle("is-sticky", this.sticky);
            if (this.resizeObserver) {
                if (this.sticky) {
                    this.resizeObserver.observe(this.el);
                } else {
                    this.resizeObserver.unobserve(this.el);
                }
            }
            this.updateHeightVar();
        };

        this.observer = new IntersectionObserver(
            ([entry]) => {
                // isIntersecting === any overlap with the viewport (threshold 0).
                // Sticky when the sentinel is completely out of view (scrolled up).
                this.applySticky(!entry.isIntersecting);
            },
            { threshold: 0, rootMargin: "0px" }
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
        if (this.resizeObserver) {
            this.resizeObserver.disconnect();
            this.resizeObserver = null;
        }
        if (this.sentinel && this.sentinel.parentElement) {
            this.sentinel.parentElement.removeChild(this.sentinel);
        }
        document.documentElement.style.removeProperty("--event-header-height");
    },

    syncEventHeaderHeightVar() {
        if (!this.sticky) return;
        const h = this.el.offsetHeight;
        document.documentElement.style.setProperty("--event-header-height", h + "px");
    },

    updateHeightVar() {
        if (this.sticky) {
            this.syncEventHeaderHeightVar();
        } else {
            document.documentElement.style.removeProperty("--event-header-height");
        }
    },
};

export default StickyEventHeader;
