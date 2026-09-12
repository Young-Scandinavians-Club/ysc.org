// Overlay a loading spinner on an <img> or <iframe> preview until it finishes
// loading, then fade it out. On <img> load failure, swap the spinner for an
// error message.
//
// The overlay element's id is passed via `data-loading-overlay` on the hooked
// element. The overlay carries `phx-update="ignore"` so this hook fully owns its
// visibility; navigating between attachments swaps in a fresh overlay + element
// because their ids include the attachment index.
//
// The overlay's markup carries a static `flex` class (to center the spinner).
// The `[hidden]` attribute selector and `.flex` utility class have equal CSS
// specificity, and Tailwind's utilities layer loads after preflight, so `.flex`
// wins the cascade and the `hidden` attribute alone would NOT actually hide the
// element — it would stay laid out (just faded via opacity) and keep swallowing
// clicks/scroll over the preview underneath. `classList.remove("flex")` here
// removes that competing rule so `[hidden]` can take effect.
const FADE_MS = 200;

const MediaLoadState = {
    overlay() {
        const id = this.el.dataset.loadingOverlay;
        return id ? document.getElementById(id) : null;
    },

    hideOverlay() {
        const overlay = this.overlay();
        if (!overlay || overlay.dataset.state === "hidden") return;

        overlay.dataset.state = "hidden";
        overlay.classList.add("opacity-0");
        this.fadeTimer = window.setTimeout(() => {
            overlay.setAttribute("hidden", "");
            overlay.classList.remove("flex");
        }, FADE_MS);
    },

    showError() {
        const overlay = this.overlay();
        if (!overlay) return;

        window.clearTimeout(this.fadeTimer);
        overlay.dataset.state = "error";
        overlay.removeAttribute("hidden");
        overlay.classList.add("flex");
        overlay.classList.remove("opacity-0");

        const spinner = overlay.querySelector("[data-load-spinner]");
        if (spinner) spinner.remove();

        const label = overlay.querySelector("[data-load-label]");
        if (label) {
            label.textContent =
                overlay.dataset.errorLabel || "Couldn’t load preview";
        }
    },

    arm() {
        // A cached <img> can already be `complete` before the hook mounts (or
        // after a LiveView patch), and won't fire "load" again.
        if (this.el.tagName === "IMG" && this.el.complete) {
            if (this.el.naturalWidth === 0) {
                this.showError();
            } else {
                this.hideOverlay();
            }
            return;
        }

        // addEventListener de-dupes identical listeners, so re-arming is safe.
        this.el.addEventListener("load", this.onLoad, { once: true });
        this.el.addEventListener("error", this.onError, { once: true });
    },

    mounted() {
        this.onLoad = () => this.hideOverlay();
        this.onError = () => this.showError();
        this.arm();
    },

    updated() {
        this.arm();
    },

    destroyed() {
        window.clearTimeout(this.fadeTimer);
        this.el.removeEventListener("load", this.onLoad);
        this.el.removeEventListener("error", this.onError);
    },
};

export default MediaLoadState;
