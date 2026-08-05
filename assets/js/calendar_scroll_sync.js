// Preserves the calendar's horizontal scroll position across LiveView patches
// (e.g. opening/closing the booking modal via push_patch), since a DOM patch
// that touches this container's children resets its native scrollLeft to 0.
const CalendarScrollSync = {
    mounted() {
        this.scrollLeft = this.el.scrollLeft;
        this.handleScroll = () => {
            this.scrollLeft = this.el.scrollLeft;
        };
        this.el.addEventListener("scroll", this.handleScroll, { passive: true });
    },

    updated() {
        if (this.el.scrollLeft !== this.scrollLeft) {
            this.el.scrollLeft = this.scrollLeft;
        }
    },

    destroyed() {
        if (this.handleScroll) {
            this.el.removeEventListener("scroll", this.handleScroll);
        }
    }
};

export default CalendarScrollSync;
