// Forwards LiveToast's phx:clear-flash push events to the server. Promoted
// toasts hide the flash elements that normally handle this, so without a
// dedicated listener the flash assign sticks around and toasts reappear.
import { pushEventIfConnected } from "./live_view_safe_push";

export const ToastFlashBridge = {
  mounted() {
    this.onClearFlash = (event) => {
      const key = event.detail?.key;
      if (!key) return;

      const keyStr = String(key);

      // Guarded push: a stale toast can emit phx:clear-flash mid-navigation, when
      // this hook's LiveView is already disconnected. Raw pushEvent would reject
      // asynchronously ("LiveView not connected") and surface as an unhandled
      // rejection.
      pushEventIfConnected(this, "lv:clear-flash", { key: keyStr });
      pushEventIfConnected(this, "lv:clear-flash", { key: `${keyStr}_toast_title` });
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
