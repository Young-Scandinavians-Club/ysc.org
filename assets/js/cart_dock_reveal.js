// Keeps the floating cart pill hidden while the page's own cart link (the
// element named by data-reveal-after) is on screen, and reveals it once that
// link has scrolled out of view.
//
// LiveView patches drop attributes the server did not render, so the state is
// kept on the hook and re-applied in updated().
const CartDockReveal = {
    mounted() {
        this.revealed = false;
        const target = document.getElementById(this.el.dataset.revealAfter);

        if (!target || !("IntersectionObserver" in window)) {
            this.revealed = true;
            this.apply();
            return;
        }

        this.observer = new IntersectionObserver(([entry]) => {
            this.revealed = !entry.isIntersecting;
            this.apply();
        });
        this.observer.observe(target);
        this.apply();
    },

    updated() {
        this.apply();
    },

    destroyed() {
        if (this.observer) this.observer.disconnect();
    },

    apply() {
        this.el.toggleAttribute("data-revealed", this.revealed);
    },
};

export default CartDockReveal;
