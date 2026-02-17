function callbackEvent(self, name, eventName) {
    return (payload) => {
        const events = self.el.dataset.events || "";

        if (events.split(",").indexOf(name) > -1) {
            self.pushEventTo(self.el, `turnstile:${eventName || name}`, payload);
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
        waitForTurnstile(() => {
            turnstile.render(this.el, {
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
                    turnstile.reset(this.el);
                });
            }
        });

        this.handleEvent("turnstile:remove", (event) => {
            if (!event.id || event.id === this.el.id) {
                waitForTurnstile(() => {
                    turnstile.remove(this.el);
                });
            }
        });
    },
};

export default Turnstile;