// Scroll-linked progress bar. It tracks the scroll position 1:1, so it has no
// transition (any easing would lag the content under the user's finger) and it
// animates `transform` rather than `width` so no layout work happens per frame.
export default {
  mounted() {
    this.updateProgress = () => {
      const progressBar = document.getElementById("reading-progress");
      if (!progressBar) return;

      const windowHeight = window.innerHeight;
      const documentHeight = document.documentElement.scrollHeight;
      const scrollTop = window.pageYOffset || document.documentElement.scrollTop;
      const scrollableHeight = documentHeight - windowHeight;
      const progress = scrollableHeight > 0 ? scrollTop / scrollableHeight : 0;

      progressBar.style.transform = `scaleX(${Math.min(1, Math.max(0, progress))})`;
    };

    this.updateProgress();
    window.addEventListener("scroll", this.updateProgress, { passive: true });
  },

  // A LiveView patch resets the inline style to the server's initial value.
  updated() {
    this.updateProgress();
  },

  destroyed() {
    if (this.updateProgress) {
      window.removeEventListener("scroll", this.updateProgress);
    }
  }
};
