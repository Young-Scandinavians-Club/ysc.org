import { altKeyLabel, applyPlatformKeyLabels } from "./platform_keys";

// Keyboard navigation hook for the event ticket check-in desk.
//
// Attach with phx-hook="EventCheckInKeyboard" on the search form.
//
// Supported keys (active anywhere on the page):
//   ArrowDown / ArrowUp  — move the highlight through pending ticket rows
//   Enter                — check in (toggle) the highlighted ticket
//   Alt+1 / Alt+2 / Alt+3 — instantly check in the 1st, 2nd, or 3rd pending ticket
//   Escape               — clear search and refocus input
//
// Shortcut badges (alt 1, alt 2, alt 3) are injected into placeholder spans
// in the first 3 pending rows. They are refreshed whenever the component
// updates (e.g. after a check-in removes a row from the list).

const ROW_SELECTOR = "[data-checkin-row]";
const BTN_SELECTOR = "[data-checkin-btn]";
const BADGE_SELECTOR = ".checkin-kbd-badge";
const FOCUSED_CLASS = "keyboard-focused";

const EventCheckInKeyboard = {
    mounted() {
        this._selectedIndex = -1;
        this._onKeyDown = this._handleKeyDown.bind(this);
        window.addEventListener("keydown", this._onKeyDown);
        this._refreshBadges();
    },

    updated() {
        // Rows may have been added/removed — reapply highlight, badges, and platform key labels.
        const rows = this._rows();
        // Clamp index in case rows shrank.
        if (this._selectedIndex >= rows.length) {
            this._selectedIndex = rows.length - 1;
        }
        this._applyHighlight(this._selectedIndex);
        this._refreshBadges();
        applyPlatformKeyLabels();
    },

    destroyed() {
        window.removeEventListener("keydown", this._onKeyDown);
    },

    _rows() {
        return Array.from(document.querySelectorAll(ROW_SELECTOR));
    },

    _handleKeyDown(e) {
        const active = document.activeElement;
        const tag = active ? active.tagName : "";
        const isOtherInput =
            (tag === "INPUT" && active.id !== "check-in-search-input") ||
            tag === "TEXTAREA" ||
            tag === "SELECT";
        if (isOtherInput) return;

        const rows = this._rows();

        // Handle Alt+1/2/3 before the key switch — must use e.code because on Mac,
        // Option+number produces a composed character in e.key (e.g. "¡") not a digit.
        if (e.altKey && ["Digit1", "Digit2", "Digit3"].includes(e.code)) {
            e.preventDefault();
            const idx = parseInt(e.code.replace("Digit", ""), 10) - 1;
            if (idx < rows.length) this._actOn(rows[idx]);
            return;
        }

        if (rows.length === 0 && e.key !== "Escape") return;

        switch (e.key) {
            case "ArrowDown":
                e.preventDefault();
                this._move(rows, 1);
                break;

            case "ArrowUp":
                e.preventDefault();
                this._move(rows, -1);
                break;

            case "Enter":
                e.preventDefault();
                if (this._selectedIndex >= 0 && this._selectedIndex < rows.length) {
                    this._actOn(rows[this._selectedIndex]);
                } else if (rows.length === 1) {
                    this._actOn(rows[0]);
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

    _move(rows, direction) {
        const len = rows.length;
        if (len === 0) return;

        let next = this._selectedIndex + direction;
        if (next < 0) next = len - 1;
        if (next >= len) next = 0;

        this._selectedIndex = next;
        this._applyHighlight(next);
        rows[next].scrollIntoView({ block: "nearest", behavior: "smooth" });
    },

    _applyHighlight(index) {
        document.querySelectorAll(ROW_SELECTOR).forEach((el, i) => {
            el.classList.toggle(FOCUSED_CLASS, i === index);
        });
    },

    _actOn(rowEl) {
        const btn = rowEl.querySelector(BTN_SELECTOR);
        if (btn && !btn.disabled) {
            btn.click();
        }
    },

    // Inject "alt 1/2/3" badges into the first 3 badge placeholder spans.
    // Placeholders are rendered by the server as empty <span class="checkin-kbd-badge">.
    _refreshBadges() {
        const kbdBase = "inline-flex justify-center items-center py-0.5 bg-white border border-zinc-300 font-mono text-[10px] text-zinc-400 rounded";
        const kbdShadow = "box-shadow: 0 2px 0 0 #d1d5db"; // zinc-300
        const altLabel = altKeyLabel();

        const badges = Array.from(document.querySelectorAll(BADGE_SELECTOR));
        badges.forEach((span, i) => {
            if (i < 3) {
                span.style.display = "inline-flex";
                span.style.alignItems = "center";
                span.style.gap = "2px";
                span.innerHTML =
                    `<kbd class="${kbdBase}" style="min-height:1.375rem;padding-left:0.375rem;padding-right:0.375rem;${kbdShadow}">${altLabel}</kbd>` +
                    `<kbd class="${kbdBase}" style="min-height:1.375rem;min-width:1.375rem;padding-left:0.25rem;padding-right:0.25rem;${kbdShadow}">${i + 1}</kbd>`;
                span.removeAttribute("hidden");
            } else {
                span.innerHTML = "";
                span.setAttribute("hidden", "");
                span.style.display = "";
            }
        });
    },
};

export default EventCheckInKeyboard;
