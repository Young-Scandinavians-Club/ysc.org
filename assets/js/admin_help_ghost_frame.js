// Scales ghost-preview iframes to fit the guide screenshot frame and wires
// hotspot tooltips (same behaviour as AdminHelpHotspots).

const VIEWPORT_W = 1280;
const VIEWPORT_H = 800;

const AdminHelpGhostFrame = {
  mounted() {
    this.viewport = this.el.querySelector(".admin-help-ghost-viewport");
    this.iframe = this.el.querySelector(".admin-help-ghost-iframe");

    if (this.viewport && this.iframe) {
      this.scaleFrame = this.scaleFrame.bind(this);
      this.syncIframeSidebar = this.syncIframeSidebar.bind(this);
      this.onSidebarToggle = this.onSidebarToggle.bind(this);

      this.syncIframeNavigation();
      this.syncIframeSidebar();
      this.scaleFrame();
      this._resizeObserver = new ResizeObserver(() => this.scaleFrame());
      this._resizeObserver.observe(this.viewport);
      document.addEventListener("admin:toggle-sidebar", this.onSidebarToggle);
    }

    this._hotspotAbort = new AbortController();
    this.wireHotspots();
  },

  updated() {
    if (this.viewport && this.iframe) {
      this.syncIframeNavigation();
      this.syncIframeSidebar();
      this.scaleFrame();
    }

    this._hotspotAbort?.abort();
    this._hotspotAbort = new AbortController();
    this.wireHotspots();
  },

  destroyed() {
    this._resizeObserver?.disconnect();
    document.removeEventListener("admin:toggle-sidebar", this.onSidebarToggle);
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

  onSidebarToggle() {
    // Wait for the html class toggle from admin:toggle-sidebar to apply.
    requestAnimationFrame(() => this.syncIframeSidebar());
  },

  syncIframeNavigation() {
    const desired =
      this.iframe.dataset.ghostSrc || this.iframe.getAttribute("src");
    if (!desired) return;

    const desiredUrl = new URL(desired, window.location.origin);
    const currentUrl = new URL(this.iframe.src, window.location.origin);

    const scrollChanged =
      desiredUrl.searchParams.get("scroll_to") !==
      currentUrl.searchParams.get("scroll_to");
    const pathChanged = desiredUrl.pathname !== currentUrl.pathname;

    if (pathChanged || scrollChanged) {
      this.iframe.src = desired;
    }
  },

  syncIframeSidebar() {
    const collapsed = document.documentElement.classList.contains("sidebar-collapsed");
    const url = new URL(this.iframe.src, window.location.origin);
    const next = collapsed ? "1" : "0";

    if (url.searchParams.get("sidebar_collapsed") !== next) {
      url.searchParams.set("sidebar_collapsed", next);
      this.iframe.src = url.toString();
    }
  },

  scaleFrame() {
    const w = this.viewport.clientWidth;
    const scale = w / VIEWPORT_W;
    this.iframe.style.width = `${VIEWPORT_W}px`;
    this.iframe.style.height = `${VIEWPORT_H}px`;
    this.iframe.style.transform = `scale(${scale})`;
    this.iframe.style.transformOrigin = "top left";
    this.viewport.style.height = `${VIEWPORT_H * scale}px`;
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

export default AdminHelpGhostFrame;
