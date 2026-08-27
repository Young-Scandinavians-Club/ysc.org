/**
 * StopClick Hook
 *
 * Stops `click` events from bubbling past the element it's attached to.
 * Used to keep clicks inside an actions menu from also triggering a
 * clickable parent row. Replaces inline `onclick="event.stopPropagation()"`,
 * which the Content Security Policy (script-src-attr) blocks.
 *
 * Usage:
 *   <div id="row-1-actions-stop" phx-hook="StopClick">...</div>
 */
export default {
    mounted() {
        this.stop = (e) => e.stopPropagation();
        this.el.addEventListener("click", this.stop);
    },

    destroyed() {
        this.el.removeEventListener("click", this.stop);
    },
};
