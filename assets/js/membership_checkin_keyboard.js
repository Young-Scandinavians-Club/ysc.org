import { altKeyLabel, applyPlatformKeyLabels } from "./platform_keys";

// Keyboard navigation hook for the membership check-in desk.
//
// Attach with phx-hook="MembershipCheckInKeyboard" on the search input.
//
// Supported keys (while the input is focused OR anywhere on the page):
//   ArrowDown / ArrowUp  — move the highlighted result
//   Enter                — check in (or undo) the highlighted result
//   1 / 2 / 3           — instantly act on the Nth result
//   Escape               — clear search and return focus to input
//
// The hook tracks a `selectedIndex` in JS-only state so the highlight
// responds instantly without a server round-trip. The actual check-in
// is still dispatched as a phx-click on the target button.

const RESULT_SELECTOR = "[data-checkin-index]";
const FOCUSED_CLASS = "keyboard-focused";

const MembershipCheckInKeyboard = {
    mounted() {
        this._selectedIndex = -1;
        this._onKeyDown = this._handleKeyDown.bind(this);
        window.addEventListener("keydown", this._onKeyDown);
        applyPlatformKeyLabels();
    },

    updated() {
        // Re-apply focus highlight and platform key labels after every LiveView patch.
        this._applyHighlight(this._selectedIndex);
        applyPlatformKeyLabels();
    },

    destroyed() {
        window.removeEventListener("keydown", this._onKeyDown);
    },

    _results() {
        return Array.from(document.querySelectorAll(RESULT_SELECTOR));
    },

    _handleKeyDown(e) {
        // Ignore if focus is inside an input other than our search bar,
        // a textarea, or a select — don't hijack other form fields.
        const active = document.activeElement;
        const tag = active ? active.tagName : "";
        const isOtherInput =
            (tag === "INPUT" && active.id !== "member-search-input") ||
            tag === "TEXTAREA" ||
            tag === "SELECT";
        if (isOtherInput) return;

        const results = this._results();

        // Handle Alt+1/2/3 before the key switch — must use e.code because on Mac,
        // Option+number produces a composed character in e.key (e.g. "¡") not a digit.
        if (e.altKey && ["Digit1", "Digit2", "Digit3"].includes(e.code)) {
            e.preventDefault();
            const idx = parseInt(e.code.replace("Digit", ""), 10) - 1;
            if (idx < results.length) this._actOn(results[idx]);
            return;
        }

        if (results.length === 0 && e.key !== "Escape") return;

        switch (e.key) {
            case "ArrowDown":
                e.preventDefault();
                this._move(results, 1);
                break;

            case "ArrowUp":
                e.preventDefault();
                this._move(results, -1);
                break;

            case "Enter":
                e.preventDefault();
                if (this._selectedIndex >= 0 && this._selectedIndex < results.length) {
                    this._actOn(results[this._selectedIndex]);
                } else if (results.length === 1) {
                    this._actOn(results[0]);
                }
                break;

            case "Escape":
                e.preventDefault();
                this._selectedIndex = -1;
                this._applyHighlight(-1);
                this.pushEvent("clear-search", {});
                break;
        }
    },

    _move(results, direction) {
        const len = results.length;
        if (len === 0) return;

        let next = this._selectedIndex + direction;
        if (next < 0) next = len - 1;
        if (next >= len) next = 0;

        this._selectedIndex = next;
        this._applyHighlight(next);

        // Scroll the highlighted row into view smoothly.
        results[next].scrollIntoView({ block: "nearest", behavior: "smooth" });
    },

    _applyHighlight(index) {
        document.querySelectorAll(RESULT_SELECTOR).forEach((el, i) => {
            el.classList.toggle(FOCUSED_CLASS, i === index);
        });
    },

    _actOn(resultEl) {
        // Find the primary action button: check-in, undo, or nothing (disabled).
        const btn = resultEl.querySelector("[data-checkin-btn]");
        if (btn && !btn.disabled) {
            btn.click();
        }
    },
};

export default MembershipCheckInKeyboard;
