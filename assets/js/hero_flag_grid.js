/**
 * Cross-fades a random number of flag tiles from grayscale into color at a time.
 * The count itself is random each tick (0 up to MAX_LIT) so some ticks light
 * nothing, some light a couple, some light a bunch. Respects prefers-reduced-motion
 * by leaving every tile grayscale and static.
 */
const INTERVAL_MS = 2400;
const MIN_LIT = 0;
const MAX_LIT = 12;

export default {
    mounted() {
        this.cells = Array.from(this.el.querySelectorAll(".hero-flag-grid__cell"));
        if (this.cells.length === 0) return;
        if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

        this.active = [];
        this.lightRandomCells = this.lightRandomCells.bind(this);
        this.timer = setInterval(this.lightRandomCells, INTERVAL_MS);
        this.lightRandomCells();
    },

    lightRandomCells() {
        const count = Math.min(
            this.cells.length,
            MIN_LIT + Math.floor(Math.random() * (MAX_LIT - MIN_LIT + 1)),
        );
        const next = new Set();
        while (next.size < count) {
            next.add(this.cells[Math.floor(Math.random() * this.cells.length)]);
        }

        this.active.forEach((cell) => {
            if (!next.has(cell)) cell.classList.remove("is-lit");
        });
        next.forEach((cell) => cell.classList.add("is-lit"));
        this.active = Array.from(next);
    },

    destroyed() {
        clearInterval(this.timer);
    },
};
