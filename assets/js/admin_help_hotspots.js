// Annotated screenshot hotspots for admin help guides.
// Shows a tooltip on hover/focus for each pulsing hotspot button.

const AdminHelpHotspots = {
  mounted() {
    this._hotspotAbort = new AbortController();
    this.wireHotspots();
  },

  updated() {
    this._hotspotAbort?.abort();
    this._hotspotAbort = new AbortController();
    this.wireHotspots();
  },

  destroyed() {
    this._hotspotAbort?.abort();
    this.hideTooltip();
  },

  wireHotspots() {
    const signal = this._hotspotAbort.signal;

    this.el.querySelectorAll(".admin-help-hotspot").forEach((btn) => {
      btn.addEventListener("mouseenter", () => this.showTooltip(btn), { signal });
      btn.addEventListener("focus", () => this.showTooltip(btn), { signal });
      btn.addEventListener("mouseleave", () => this.hideTooltip(), { signal });
      btn.addEventListener("blur", () => this.hideTooltip(), { signal });
    });
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
