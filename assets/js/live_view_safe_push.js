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
 * @returns {boolean} whether the event was sent
 */
export function pushEventIfConnected(hook, event, payload = {}) {
    if (!liveViewConnected(hook)) return false;
    try {
        hook.pushEvent(event, payload);
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
        hook.pushEventTo(target, event, payload);
        return true;
    } catch (err) {
        console.error("[live_view_safe_push] pushEventTo failed", event, err);
        return false;
    }
}
