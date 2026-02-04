export default {
  mounted() {
    this.updateProgress = () => {
      const progressBar = document.getElementById("reading-progress");
      if (!progressBar) return;

      const windowHeight = window.innerHeight;
      const documentHeight = document.documentElement.scrollHeight;
      const scrollTop = window.pageYOffset || document.documentElement.scrollTop;
      const scrollableHeight = documentHeight - windowHeight;
      const progress = scrollableHeight > 0 ? (scrollTop / scrollableHeight) * 100 : 0;

      progressBar.style.width = `${Math.min(100, Math.max(0, progress))}%`;
    };

    this.updateProgress();
    window.addEventListener("scroll", this.updateProgress);
  },

  destroyed() {
    if (this.updateProgress) {
      window.removeEventListener("scroll", this.updateProgress);
    }
  }
};

