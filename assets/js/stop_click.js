/**
 * StopClick Hook
 *
 * Keeps clicks inside an actions menu from also triggering a clickable parent
 * row (e.g. a `Flop.Phoenix.table` `row_click` on the surrounding `<tr>`).
 * Replaces inline `onclick="event.stopPropagation()"`, which the Content
 * Security Policy (`script-src` with a nonce + `strict-dynamic`) blocks.
 *
 * Naively calling `event.stopPropagation()` for every click here also stops the
 * event from reaching LiveView's delegated click handler on `window`, which
 * kills the menu's own `phx-click`s (the trigger never opens, items never fire).
 *
 * LiveView only ever acts on the *closest* `phx-click` to the target, so a real
 * click on the trigger or a menu item can safely bubble to `window` without the
 * parent row reacting. We therefore only swallow "dead zone" clicks -- on the
 * menu's padding, dividers, or gaps -- which would otherwise resolve to the
 * row's `phx-click`.
 *
 * Usage:
 *   <div id="row-1-actions-stop" phx-hook="StopClick">...</div>
 */
export default {
    mounted() {
        this.stop = (e) => {
            const control = e.target.closest("[phx-click], a[href], button");
            if (!control || !this.el.contains(control)) {
                e.stopPropagation();
            }
        };
        this.el.addEventListener("click", this.stop);
    },

    destroyed() {
        this.el.removeEventListener("click", this.stop);
    },
};
