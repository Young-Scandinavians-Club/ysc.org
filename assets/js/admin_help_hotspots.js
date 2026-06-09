// Annotated screenshot hotspots for admin help guides.
// Shows a tooltip on hover/focus for each pulsing hotspot button.

const AdminHelpHotspots = {
  mounted() {
    this.hotspots = this.el.querySelectorAll(".admin-help-hotspot");
    this.hotspots.forEach((btn) => {
      btn.addEventListener("mouseenter", () => this.showTooltip(btn));
      btn.addEventListener("focus", () => this.showTooltip(btn));
      btn.addEventListener("mouseleave", () => this.hideTooltip());
      btn.addEventListener("blur", () => this.hideTooltip());
    });
  },

  destroyed() {
    this.hideTooltip();
  },

  showTooltip(btn) {
    this.hideTooltip();
    const label = btn.getAttribute("data-hotspot-label");
    if (!label) return;

    const tip = document.createElement("div");
    tip.className = "admin-help-hotspot-tooltip";
    tip.textContent = label;
    tip.setAttribute("role", "tooltip");
    document.body.appendChild(tip);

    const rect = btn.getBoundingClientRect();
    tip.style.left = `${rect.left + rect.width / 2}px`;
    tip.style.top = `${rect.top - 8}px`;
    this._tooltip = tip;
  },

  hideTooltip() {
    if (this._tooltip) {
      this._tooltip.remove();
      this._tooltip = null;
    }
  },
};

export default AdminHelpHotspots;
