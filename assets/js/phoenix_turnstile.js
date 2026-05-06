import { pushEventToIfConnected } from "./live_view_safe_push";

function callbackEvent(self, name, eventName) {
    return (payload) => {
        if (self._turnstileDestroyed || !self.el?.isConnected) return;

        const events = self.el.dataset.events || "";

        if (events.split(",").indexOf(name) > -1) {
            pushEventToIfConnected(self, self.el, `turnstile:${eventName || name}`, payload);
        }
    };
}

// Wait for Turnstile library to be available
function waitForTurnstile(callback, maxAttempts = 50, attempt = 0) {
    if (typeof window.turnstile !== "undefined") {
        callback();
    } else if (attempt < maxAttempts) {
        // Check every 100ms for up to 5 seconds
        setTimeout(() => {
            waitForTurnstile(callback, maxAttempts, attempt + 1);
        }, 100);
    } else {
        console.error(
            "Turnstile library failed to load after 5 seconds. Please check your internet connection and CSP settings.",
        );
    }
}

export const Turnstile = {
    mounted() {
        this._turnstileDestroyed = false;

        waitForTurnstile(() => {
            if (this._turnstileDestroyed || !this.el?.isConnected) return;
            turnstile.render(this.el, {
                theme: "light",
                callback: callbackEvent(this, "success"),
                "error-callback": callbackEvent(this, "error"),
                "expired-callback": callbackEvent(this, "expired"),
                "before-interactive-callback": callbackEvent(
                    this,
                    "beforeInteractive",
                    "before-interactive",
                ),
                "after-interactive-callback": callbackEvent(
                    this,
                    "afterInteractive",
                    "after-interactive",
                ),
                "unsupported-callback": callbackEvent(this, "unsupported"),
                "timeout-callback": callbackEvent(this, "timeout"),
            });
        });

        this.handleEvent("turnstile:refresh", (event) => {
            if (!event.id || event.id === this.el.id) {
                waitForTurnstile(() => {
                    if (this._turnstileDestroyed || !this.el?.isConnected) return;
                    turnstile.reset(this.el);
                });
            }
        });

        this.handleEvent("turnstile:remove", (event) => {
            if (!event.id || event.id === this.el.id) {
                waitForTurnstile(() => {
                    if (this._turnstileDestroyed || !this.el?.isConnected) return;
                    turnstile.remove(this.el);
                });
            }
        });
    },

    destroyed() {
        this._turnstileDestroyed = true;
    },
};

export default Turnstile;
