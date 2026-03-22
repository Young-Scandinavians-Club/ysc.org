// Unified countdown hook for Phoenix LiveView.
//
// Data attributes:
//   data-expires-at        — Required. ISO 8601 datetime to count down to.
//   data-countdown-target  — Optional CSS selector for a child element that
//                            receives the formatted time text. When omitted the
//                            hook element itself is used.
//   data-expire-event      — Optional LiveView event name pushed when the
//                            countdown reaches zero.
//   data-expire-text       — Optional text shown when expired (default: "00:00").
//   data-color-self        — When present the hook replaces its own className
//                            with color classes based on remaining time.
//   data-color-container   — When present the hook manages bg/border classes on
//                            itself and an animate-pulse class on the countdown
//                            target element.
const Countdown = {
    mounted() {
        this._init();
    },

    updated() {
        if (this.el.dataset.expiresAt !== this._rawExpiry) this._init();
    },

    destroyed() {
        this._cleanup();
    },

    _init() {
        this._rawExpiry = this.el.dataset.expiresAt;
        if (!this._rawExpiry) return;

        this._expiry = new Date(this._rawExpiry);
        if (isNaN(this._expiry.getTime())) return;

        this._cleanup();
        this._tick();
        this._interval = setInterval(() => this._tick(), 1000);
    },

    _cleanup() {
        if (this._interval) {
            clearInterval(this._interval);
            this._interval = null;
        }
    },

    _tick() {
        const diffMs = this._expiry - new Date();
        const expired = diffMs <= 0;
        const totalSec = Math.max(0, Math.floor(diffMs / 1000));
        const h = Math.floor(totalSec / 3600);
        const m = Math.floor((totalSec % 3600) / 60);
        const s = totalSec % 60;

        const targetSel = this.el.dataset.countdownTarget;
        const displayEl = targetSel
            ? this.el.querySelector(targetSel)
            : this.el;

        if (displayEl) {
            if (expired) {
                displayEl.textContent =
                    this.el.dataset.expireText || "00:00";
            } else {
                displayEl.textContent =
                    h > 0
                        ? `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`
                        : `${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
            }
        }

        if (this.el.dataset.colorSelf !== undefined) {
            this._applySelfColor(m, expired);
        }

        if (this.el.dataset.colorContainer !== undefined) {
            this._applyContainerColor(m, expired, displayEl);
        }

        if (expired) {
            this._cleanup();
            const event = this.el.dataset.expireEvent;
            if (event) this.pushEvent(event, {});
        }
    },

    _applySelfColor(minutes, expired) {
        if (expired) {
            this.el.className = "font-bold text-red-600";
        } else if (minutes < 2) {
            this.el.className = "font-bold text-orange-600";
        } else if (minutes < 5) {
            this.el.className = "font-bold text-yellow-600";
        } else {
            this.el.className = "font-bold text-blue-900";
        }
    },

    _applyContainerColor(minutes, expired, countdownEl) {
        const el = this.el;

        el.classList.remove(
            "bg-blue-50",
            "border-blue-200",
            "bg-amber-50",
            "border-amber-200",
            "bg-rose-50",
            "border-rose-200",
            "border-red-500",
        );

        if (expired || minutes < 1) {
            el.classList.add("bg-rose-50", "border-rose-200");
            if (expired) el.classList.add("border-red-500");
            if (countdownEl) countdownEl.classList.add("animate-pulse");
        } else if (minutes < 5) {
            el.classList.add("bg-amber-50", "border-amber-200");
            if (countdownEl) countdownEl.classList.remove("animate-pulse");
        } else {
            el.classList.add("bg-blue-50", "border-blue-200");
            if (countdownEl) countdownEl.classList.remove("animate-pulse");
        }
    },
};

export default Countdown;
