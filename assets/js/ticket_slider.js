// TicketSlider — native scroll-snap carousel for the ticket QR page.
//
// The slider container uses overflow-x: scroll + scroll-snap-type so the
// browser handles all touch physics, momentum, and rubber-banding natively.
// This hook manages the dot indicators and prev/next buttons.

export default {
  mounted() {
    this.total = this.el.querySelectorAll("[data-slide]").length;
    this.dotsContainer = this.el.querySelector("[data-slider-dots]");
    this.prevBtn = this.el.querySelector("[data-slider-prev]");
    this.nextBtn = this.el.querySelector("[data-slider-next]");
    this.viewport = this.el.querySelector("[data-slider-viewport]");

    // Flag used to suppress scroll events fired during programmatic smooth-scroll.
    // Without it the dots jitter: scrollTo() sets index=N immediately, then the
    // scroll event fires with an intermediate position and resets dots back to N-1.
    this._programmatic = false;

    if (this.total <= 1) return;

    this.prevBtn?.addEventListener("click", () => this.scrollTo(this.currentIndex() - 1));
    this.nextBtn?.addEventListener("click", () => this.scrollTo(this.currentIndex() + 1));

    // Keep dots and buttons in sync during native swipe (touch / trackpad).
    // Ignored while a programmatic scroll is in flight.
    this.viewport?.addEventListener("scroll", () => this.onScroll(), { passive: true });

    this.updateControls(0);
  },

  currentIndex() {
    if (!this.viewport) return 0;
    const slideWidth = this.viewport.scrollWidth / this.total;
    return Math.round(this.viewport.scrollLeft / slideWidth);
  },

  scrollTo(index) {
    if (!this.viewport) return;
    const clamped = Math.max(0, Math.min(index, this.total - 1));
    const slideWidth = this.viewport.scrollWidth / this.total;

    // Suppress onScroll for the duration of the smooth animation (~400 ms).
    // We update the controls ourselves right here so the response is instant.
    this._programmatic = true;
    clearTimeout(this._programmaticTimer);
    this._programmaticTimer = setTimeout(() => {
      this._programmatic = false;
      // Sync once the animation settles in case the final position differs.
      this.updateControls(this.currentIndex());
    }, 500);

    this.viewport.scrollTo({ left: clamped * slideWidth, behavior: "smooth" });
    this.updateControls(clamped);
  },

  onScroll() {
    // Skip intermediate positions fired during a programmatic smooth-scroll.
    if (this._programmatic) return;
    this.updateControls(this.currentIndex());
  },

  updateControls(index) {
    if (this.dotsContainer) {
      this.dotsContainer.querySelectorAll("[data-dot]").forEach((dot, i) => {
        const active = i === index;
        // Note: classList.toggle uses the plain class string — no CSS escaping needed.
        dot.classList.toggle("w-3", active);
        dot.classList.toggle("h-3", active);
        dot.classList.toggle("w-2.5", !active);   // was "w-2\\.5" — backslash is wrong here
        dot.classList.toggle("h-2.5", !active);   // was "h-2\\.5"
        dot.classList.toggle("bg-white", active);
        dot.classList.toggle("bg-zinc-400", !active);
      });
    }
    if (this.prevBtn) this.prevBtn.disabled = index === 0;
    if (this.nextBtn) this.nextBtn.disabled = index === this.total - 1;
  },
};
