function resize(el) {
  el.style.height = "auto";
  el.style.height = `${el.scrollHeight}px`;
}

function attach(el) {
  el.addEventListener("input", () => resize(el));
  resize(el);
}

module.exports = {
  mounted() {
    attach(this.el);
  },

  updated() {
    resize(this.el);
  },
};
