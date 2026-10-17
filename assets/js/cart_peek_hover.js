// Holds the "added to cart" card open while the pointer is on it.
//
// LiveView has no hover binding, so pointer enter/leave are pushed to the page
// as events; the server pauses and restarts the card's auto-dismiss timer.
const CartPeekHover = {
    mounted() {
        this.onEnter = () => this.pushEvent("pause_cart_peek", {});
        this.onLeave = () => this.pushEvent("resume_cart_peek", {});
        this.el.addEventListener("mouseenter", this.onEnter);
        this.el.addEventListener("mouseleave", this.onLeave);
    },

    destroyed() {
        this.el.removeEventListener("mouseenter", this.onEnter);
        this.el.removeEventListener("mouseleave", this.onLeave);
    },
};

export default CartPeekHover;
