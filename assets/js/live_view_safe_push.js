/**
 * Guard LiveView pushes after DOM teardown or socket disconnect (PR #219 pattern).
 * Use after async work (WebAuthn, Stripe, maps, timers, third-party callbacks).
 */

// The promise-returning form of hook.pushEvent rejects on disconnect, timeout, or
// server-side rejection. These helpers are fire-and-forget (no caller awaits the
// result), so an unattached rejection would surface as an unhandled rejection and
// page Sentry. Swallow the expected disconnect case silently; log anything else so
// a real delivery failure is still visible in the console (Sentry has no
// captureConsole integration, so this stays out of the error stream).
function swallowPushRejection(result, event) {
    if (!result || typeof result.catch !== "function") return;
    result.catch((err) => {
        const message = err && err.message ? String(err.message) : "";
        if (message.includes("not connected")) return;
        console.warn("[live_view_safe_push] pushEvent rejected", event, err);
    });
}

function liveViewConnected(hook) {
    if (!hook.el?.isConnected) return false;
    try {
        const view = hook.__view();
        return !!(view && view.isConnected());
    } catch (_) {
        return false;
    }
}

/**
 * @param {((reply: unknown) => void) | undefined} onReply
 * @returns {boolean} whether the event was sent
 */
export function pushEventIfConnected(hook, event, payload = {}, onReply) {
    if (!liveViewConnected(hook)) return false;
    try {
        const result = onReply
            ? hook.pushEvent(event, payload, onReply)
            : hook.pushEvent(event, payload);
        swallowPushRejection(result, event);
        return true;
    } catch (err) {
        console.error("[live_view_safe_push] pushEvent failed", event, err);
        return false;
    }
}

/**
 * @param {HTMLElement|string} target Element or selector (e.g. "#my-id")
 * @returns {boolean} whether the event was sent
 */
export function pushEventToIfConnected(hook, target, event, payload = {}) {
    if (!liveViewConnected(hook)) return false;
    try {
        const result = hook.pushEventTo(target, event, payload);
        swallowPushRejection(result, event);
        return true;
    } catch (err) {
        console.error("[live_view_safe_push] pushEventTo failed", event, err);
        return false;
    }
}
