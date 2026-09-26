import { loadScript } from "./load_external_asset";
import { pushEventToIfConnected } from "./live_view_safe_push";

const TURNSTILE_SRC = "https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit";

// Longest a submit waits for a token before going through anyway (the server
// then rejects it and refreshes the widget).
const SUBMIT_HOLD_MS = 15000;

// Tokens are valid for 300 s. Past this age a submit fetches a fresh one first,
// leaving margin for the round trip to the server and on to Cloudflare.
const TOKEN_MAX_AGE_MS = 240000;

// Interaction that means someone is filling in the form.
const INTERACTION_EVENTS = ["focusin", "pointerdown", "input"];

// Shown while a submit waits for a token, so the form doesn't look stuck.
const HOLD_NOTICE =
    "Checking that you're not a bot. If a checkbox appears, tick it and your form will send.";

function callbackEvent(self, name, eventName) {
    return (payload) => {
        if (self._turnstileDestroyed || !self.el?.isConnected) return;

        const events = self.el.dataset.events || "";

        if (events.split(",").indexOf(name) > -1) {
            pushEventToIfConnected(self, self.el, `turnstile:${eventName || name}`, payload);
        }
    };
}

/**
 * Cloudflare Turnstile widget hook.
 *
 * The Turnstile script (~28 KB) is not in the root layout; it loads the first
 * time a widget needs it. Invisible widgets (`appearance="interaction-only"`,
 * e.g. the homepage newsletter form) wait until someone interacts with their
 * form. Visible widgets load on mount so the box doesn't pop in and shift the
 * layout.
 *
 * A submit that happens before a token exists (fast typing, password-manager
 * autofill, an unticked checkbox) is held and re-sent once Turnstile returns a
 * token, errors out, or SUBMIT_HOLD_MS passes. While it's held, a notice under
 * the widget says what's happening.
 *
 * Tokens are single-use and expire, so a submit also waits for a fresh token
 * when the current one was already sent (e.g. the server rejected the form for
 * a validation error after checking Turnstile) or is close to expiring (e.g.
 * a long form, or a background tab that delayed Turnstile's auto-refresh).
 * The widget resets, which is usually invisible and takes a second or two.
 * Coming back to a background tab refreshes a stale token straight away, so
 * the submit usually doesn't have to wait.
 */
export const Turnstile = {
    mounted() {
        this._turnstileDestroyed = false;
        this.form = this.el.closest("form");
        // Bumped for every token Turnstile issues; compared with sentTokenSeq
        // so a token is only ever sent once. Values can't be compared: test
        // keys always issue the same dummy token.
        this.tokenSeq = 0;
        this.sentTokenSeq = 0;
        this.tokenIssuedAt = 0;
        this.createHoldNotice();

        this.onVisibilityChange = () => {
            if (document.visibilityState === "visible") this.refreshStaleToken();
        };
        document.addEventListener("visibilitychange", this.onVisibilityChange);

        const interactionOnly = this.el.dataset.appearance === "interaction-only";

        if (this.form) {
            this.onSubmit = (e) => this.holdSubmitUntilToken(e);
            // Capture on the form runs before LiveView's window-level submit listener.
            this.form.addEventListener("submit", this.onSubmit, true);
        }

        if (!interactionOnly || !this.form || this.formTouched()) {
            this.load();
        } else {
            this.onInteraction = () => this.load();
            INTERACTION_EVENTS.forEach((type) =>
                this.form.addEventListener(type, this.onInteraction, { passive: true }),
            );
        }

        this.handleEvent("turnstile:refresh", (event) => {
            if (!event.id || event.id === this.el.id) {
                this.withWidget((turnstile) => turnstile.reset(this.el));
            }
        });

        this.handleEvent("turnstile:remove", (event) => {
            if (!event.id || event.id === this.el.id) {
                this.withWidget((turnstile) => turnstile.remove(this.el));
            }
        });
    },

    destroyed() {
        this._turnstileDestroyed = true;
        this.stopListeningForInteraction();
        if (this.form && this.onSubmit) {
            this.form.removeEventListener("submit", this.onSubmit, true);
        }
        clearTimeout(this.holdTimer);
        document.removeEventListener("visibilitychange", this.onVisibilityChange);
    },

    // Typed or focused before the hook mounted (static render, slow socket).
    formTouched() {
        if (this.form.contains(document.activeElement)) return true;
        return Array.from(this.form.elements).some(
            (el) => el.type !== "hidden" && typeof el.value === "string" && el.value !== "",
        );
    },

    stopListeningForInteraction() {
        if (!this.form || !this.onInteraction) return;
        INTERACTION_EVENTS.forEach((type) =>
            this.form.removeEventListener(type, this.onInteraction),
        );
        this.onInteraction = null;
    },

    load() {
        this.stopListeningForInteraction();
        if (this.loadPromise) return this.loadPromise;

        this.loadPromise = loadScript("cf-turnstile-js", TURNSTILE_SRC)
            .then(() => this.render())
            .catch(() => {
                console.error(
                    "Turnstile library failed to load. Please check your internet connection and CSP settings.",
                );
                // Let the server decide rather than holding the submit forever.
                this.releaseHeldSubmit();
            });

        return this.loadPromise;
    },

    render() {
        if (this._turnstileDestroyed || !this.el?.isConnected || this.rendered) return;
        if (typeof window.turnstile === "undefined") return;

        const releaseThen = (fn) => (payload) => {
            this.releaseHeldSubmit();
            fn(payload);
        };

        const onToken = (fn) => (payload) => {
            this.tokenSeq += 1;
            this.tokenIssuedAt = Date.now();
            fn(payload);
        };

        window.turnstile.render(this.el, {
            theme: "light",
            callback: onToken(releaseThen(callbackEvent(this, "success"))),
            "error-callback": releaseThen(callbackEvent(this, "error")),
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
            "unsupported-callback": releaseThen(callbackEvent(this, "unsupported")),
            "timeout-callback": releaseThen(callbackEvent(this, "timeout")),
        });
        this.rendered = true;
        // Keep the notice under the widget Turnstile just appended.
        this.el.append(this.holdNotice);
    },

    // Lives inside the phx-update="ignore" widget element so LiveView patches
    // (e.g. phx-change while typing) don't remove it.
    createHoldNotice() {
        this.holdNotice = document.createElement("p");
        this.holdNotice.className = "mt-2 text-sm text-zinc-600";
        this.holdNotice.setAttribute("role", "status");
        this.holdNotice.hidden = true;
        this.el.append(this.holdNotice);
    },

    setHoldNotice(visible) {
        if (!this.holdNotice) return;
        this.holdNotice.hidden = !visible;
        // Set text only when showing so screen readers announce the change.
        this.holdNotice.textContent = visible ? HOLD_NOTICE : "";
    },

    // Refresh/remove are no-ops until the widget exists; a lazily rendered
    // widget starts fresh anyway.
    withWidget(fn) {
        if (this._turnstileDestroyed || !this.el?.isConnected) return;
        if (!this.rendered || typeof window.turnstile === "undefined") return;
        fn(window.turnstile);
    },

    hasToken() {
        const input = this.el.querySelector('input[name="cf-turnstile-response"]');
        return !!(input && input.value);
    },

    // A token Cloudflare will still accept: present, never sent, not expiring.
    hasUsableToken() {
        return (
            this.hasToken() &&
            this.tokenSeq !== this.sentTokenSeq &&
            Date.now() - this.tokenIssuedAt < TOKEN_MAX_AGE_MS
        );
    },

    refreshStaleToken() {
        if (this.hasToken() && Date.now() - this.tokenIssuedAt >= TOKEN_MAX_AGE_MS) {
            this.withWidget((turnstile) => turnstile.reset(this.el));
        }
    },

    holdSubmitUntilToken(e) {
        // A released held submit goes through with whatever token exists; if
        // it's missing the server rejects it and refreshes the widget.
        if (this.releasing || this.hasUsableToken()) {
            this.sentTokenSeq = this.tokenSeq;
            return;
        }

        e.preventDefault();
        e.stopImmediatePropagation();

        // Spent or stale token: ask Turnstile for a new one. reset() clears the
        // hidden input, and the success callback releases the submit.
        if (this.hasToken()) {
            this.withWidget((turnstile) => turnstile.reset(this.el));
        }

        const submitter = e.submitter;
        this.heldSubmit = () => {
            if (!this.form?.isConnected) return;
            const stillInForm = submitter && this.form.contains(submitter);
            this.releasing = true;
            try {
                this.form.requestSubmit(stillInForm ? submitter : undefined);
            } finally {
                this.releasing = false;
            }
        };

        clearTimeout(this.holdTimer);
        this.holdTimer = setTimeout(() => this.releaseHeldSubmit(), SUBMIT_HOLD_MS);
        this.setHoldNotice(true);
        this.load();
    },

    releaseHeldSubmit() {
        clearTimeout(this.holdTimer);
        this.setHoldNotice(false);
        const held = this.heldSubmit;
        this.heldSubmit = null;
        // Next tick, so Turnstile has filled its hidden input before we re-submit.
        if (held) setTimeout(() => !this._turnstileDestroyed && held(), 0);
    },
};

export default Turnstile;
