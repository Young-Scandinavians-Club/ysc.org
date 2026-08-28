/**
 * Guard LiveView pushes after DOM teardown or socket disconnect (PR #219 pattern).
 * Use after async work (WebAuthn, Stripe, maps, timers, third-party callbacks).
 */

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
        // pushEvent returns a promise that rejects ("LiveView not connected") if the
        // socket drops between the check above and delivery. Swallow it so it never
        // surfaces as an unhandled rejection.
        if (result && typeof result.catch === "function") {
            result.catch(() => {});
        }
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
        if (result && typeof result.catch === "function") {
            result.catch(() => {});
        }
        return true;
    } catch (err) {
        console.error("[live_view_safe_push] pushEventTo failed", event, err);
        return false;
    }
}
