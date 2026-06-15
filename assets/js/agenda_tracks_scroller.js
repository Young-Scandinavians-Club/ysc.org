function scrollItemIntoView(container, item) {
  if (!item) return;

  item.scrollIntoView({
    behavior: "smooth",
    block: "nearest",
    inline: "end",
  });
}

function setButtonVisible(button, visible) {
  if (!button) return;

  button.classList.toggle("opacity-0", !visible);
  button.classList.toggle("pointer-events-none", !visible);
  button.classList.toggle("opacity-100", visible);
}

function updateControls(el) {
  const parent = el.parentElement;
  if (!parent) return;

  const left = parent.querySelector("[data-scroll-left]");
  const right = parent.querySelector("[data-scroll-right]");

  const canScrollLeft = el.scrollLeft > 2;
  const canScrollRight = el.scrollLeft + el.clientWidth < el.scrollWidth - 2;

  setButtonVisible(left, canScrollLeft);
  setButtonVisible(right, canScrollRight);
}

function scrollByPage(el, direction) {
  const amount = Math.max(el.clientWidth * 0.85, 320) * direction;
  el.scrollBy({ left: amount, behavior: "smooth" });
}

module.exports = {
  mounted() {
    const parent = this.el.parentElement;
    this.leftButton = parent?.querySelector("[data-scroll-left]");
    this.rightButton = parent?.querySelector("[data-scroll-right]");

    this.onScroll = () => updateControls(this.el);
    this.el.addEventListener("scroll", this.onScroll);

    this.onWheel = (event) => {
      if (this.el.scrollWidth <= this.el.clientWidth) return;

      const delta = Math.abs(event.deltaX) > Math.abs(event.deltaY)
        ? event.deltaX
        : event.deltaY;

      if (delta === 0) return;

      event.preventDefault();
      this.el.scrollBy({ left: delta, behavior: "auto" });
    };
    this.el.addEventListener("wheel", this.onWheel, { passive: false });

    this.onScrollLeft = () => scrollByPage(this.el, -1);
    this.onScrollRight = () => scrollByPage(this.el, 1);

    this.leftButton?.addEventListener("click", this.onScrollLeft);
    this.rightButton?.addEventListener("click", this.onScrollRight);

    this.resizeObserver = new ResizeObserver(() => updateControls(this.el));
    this.resizeObserver.observe(this.el);

    this.handleEvent("scroll-agenda-into-view", ({ id }) => {
      requestAnimationFrame(() => {
        scrollItemIntoView(this.el, document.getElementById(id));
        updateControls(this.el);
      });
    });

    requestAnimationFrame(() => updateControls(this.el));
  },

  updated() {
    requestAnimationFrame(() => updateControls(this.el));
  },

  destroyed() {
    this.el.removeEventListener("scroll", this.onScroll);
    this.el.removeEventListener("wheel", this.onWheel);
    this.leftButton?.removeEventListener("click", this.onScrollLeft);
    this.rightButton?.removeEventListener("click", this.onScrollRight);

    if (this.resizeObserver) {
      this.resizeObserver.disconnect();
    }
  },
};
