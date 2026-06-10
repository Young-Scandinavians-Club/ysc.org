// Scrolls an embedded ghost preview to a section id (see ?scroll_to= on ghost URLs).

const AdminHelpGhostScroll = {
  mounted() {
    this.scrollToSection();
  },

  updated() {
    this.scrollToSection();
  },

  scrollToSection() {
    const sectionId = this.el.dataset.scrollTo;
    if (!sectionId) return;

    const attempt = (triesLeft) => {
      const target = document.getElementById(sectionId);

      if (target) {
        this.scrollToElement(target);
        return;
      }

      if (triesLeft > 0) {
        setTimeout(() => attempt(triesLeft - 1), 100);
      }
    };

    requestAnimationFrame(() => attempt(8));
  },

  scrollToElement(element) {
    const root = this.scrollRoot();
    const offset = 12;

    if (root === window) {
      const top =
        element.getBoundingClientRect().top + window.pageYOffset - offset;
      window.scrollTo({ top: Math.max(0, top), behavior: "instant" });
      return;
    }

    const rootRect = root.getBoundingClientRect();
    const targetRect = element.getBoundingClientRect();
    const targetTop = targetRect.top - rootRect.top + root.scrollTop;
    const smallSection = targetRect.height < root.clientHeight * 0.45;
    const scrollTop = smallSection
      ? targetTop - (root.clientHeight - targetRect.height) / 2
      : targetTop - offset;

    root.scrollTop = Math.max(0, scrollTop);
  },

  scrollRoot() {
    // Embedded ghosts always scroll inside the fixed 1280×800 root — not the
    // iframe window (which often matches content height during layout).
    if (this.el.classList.contains("admin-help-ghost-embed")) {
      return this.el;
    }

    if (this.el.scrollHeight > this.el.clientHeight + 1) {
      return this.el;
    }

    return window;
  },
};

export default AdminHelpGhostScroll;
