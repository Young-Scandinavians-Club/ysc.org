// Forwards LiveToast's phx:clear-flash push events to the server. Promoted
// toasts hide the flash elements that normally handle this, so without a
// dedicated listener the flash assign sticks around and toasts reappear.
export const ToastFlashBridge = {
  mounted() {
    this.onClearFlash = (event) => {
      const key = event.detail?.key;
      if (!key) return;

      const keyStr = String(key);

      try {
        this.pushEvent("lv:clear-flash", { key: keyStr });
        this.pushEvent("lv:clear-flash", { key: `${keyStr}_toast_title` });
      } catch (_) {}
    };

    window.addEventListener("phx:clear-flash", this.onClearFlash);
  },

  destroyed() {
    if (this.onClearFlash) {
      window.removeEventListener("phx:clear-flash", this.onClearFlash);
      this.onClearFlash = undefined;
    }
  },
};
