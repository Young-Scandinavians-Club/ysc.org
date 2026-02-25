/**
 * Shows a gradient hint at the bottom of a scroll container when there is more content to scroll to.
 * Hides the hint when the user has scrolled to the bottom.
 *
 * Usage: Wrap the scroll container in a relative parent. Put phx-hook on the scroll container.
 * Add a sibling with data-scroll-indicator for the gradient overlay.
 *
 *   <div class="relative">
 *     <div phx-hook="ScrollMoreIndicator" class="overflow-y-auto">
 *       ...content...
 *     </div>
 *     <div data-scroll-indicator class="..." aria-hidden="true"></div>
 *   </div>
 */
export default {
    mounted() {
        this.indicator = this.el.parentElement?.querySelector("[data-scroll-indicator]");
        if (!this.indicator) return;

        this.updateIndicator = () => {
            const { scrollTop, scrollHeight, clientHeight } = this.el;
            const hasMoreBelow = scrollTop + clientHeight < scrollHeight - 2; // 2px tolerance

            if (hasMoreBelow) {
                this.indicator.classList.remove("opacity-0");
                this.indicator.classList.add("opacity-100");
            } else {
                this.indicator.classList.add("opacity-0");
                this.indicator.classList.remove("opacity-100");
            }
        };

        this.el.addEventListener("scroll", this.updateIndicator);

        this.resizeObserver = new ResizeObserver(() => {
            this.updateIndicator();
        });
        this.resizeObserver.observe(this.el);

        // Initial check after a brief delay (DOM/layout may not be ready)
        requestAnimationFrame(() => this.updateIndicator());
    },

    destroyed() {
        this.el.removeEventListener("scroll", this.updateIndicator);
        if (this.resizeObserver) {
            this.resizeObserver.disconnect();
        }
    }
};
