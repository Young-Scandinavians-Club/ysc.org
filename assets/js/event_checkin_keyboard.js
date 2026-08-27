import {
    altKeyLabel,
    shiftModKeyLabel,
    applyPlatformKeyLabels,
} from "./platform_keys";

// Keyboard navigation hook for the event ticket check-in desk.
//
// Attach with phx-hook="EventCheckInKeyboard" on the search form.
//
// Supported keys (active anywhere on the page):
//   ArrowDown / ArrowUp    — move the highlight through pending ticket rows
//   Enter                  — check in (toggle) the highlighted ticket
//   Alt+1 … Alt+8          — instantly check in the Nth pending ticket
//   Shift+Cmd/Ctrl+1 … 8   — check in the whole order the Nth ticket belongs to
//   Escape                 — clear search and refocus input
//
// The quick-check-in shortcuts (and their badges) are only active once the
// operator has typed a search — on the freshly opened, unfiltered list the
// numbering would be meaningless, so nothing is shown.
//
// Shortcut badges are injected into placeholder spans:
//   .checkin-kbd-badge        — one per pending row (Alt + N)
//   .checkin-kbd-order-badge  — one per multi-ticket order group (Shift+mod + N)
// They are refreshed on every component update (e.g. after a check-in removes a
// row) and cleared whenever the search is empty.

const ROW_SELECTOR = "[data-checkin-row]";
const BTN_SELECTOR = "[data-checkin-btn]";
const BADGE_SELECTOR = ".checkin-kbd-badge";
const ORDER_BADGE_SELECTOR = ".checkin-kbd-order-badge";
const ORDER_GROUP_SELECTOR = "[data-checkin-order-group]";
const ALL_BTN_SELECTOR = "[data-checkin-all-btn]";
const SEARCH_INPUT_ID = "check-in-search-input";
const FOCUSED_CLASS = "keyboard-focused";
const MAX_SHORTCUTS = 8;

const KBD_CLASS =
    "inline-flex justify-center items-center bg-white border border-zinc-300 font-mono text-zinc-400 rounded leading-none";
// Inline styles only — this markup is injected at runtime, so Tailwind's JIT
// never sees it. box-shadow uses zinc-300.
const KBD_STYLE =
    "min-height:1rem;min-width:0.85rem;padding:1px 3px;font-size:9px;box-shadow:0 2px 0 0 #d1d5db";

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

    _searchActive() {
        const input = document.getElementById(SEARCH_INPUT_ID);
        return !!input && input.value.trim() !== "";
    },

    _handleKeyDown(e) {
        const active = document.activeElement;
        const tag = active ? active.tagName : "";
        const isOtherInput =
            (tag === "INPUT" && active.id !== SEARCH_INPUT_ID) ||
            tag === "TEXTAREA" ||
            tag === "SELECT";
        if (isOtherInput) return;

        const rows = this._rows();

        // Handle the numeric shortcuts before the key switch — must use e.code
        // because on Mac, Option+number produces a composed character in e.key
        // (e.g. "¡") rather than a digit.
        const digitMatch = /^Digit([1-8])$/.exec(e.code);
        if (digitMatch) {
            const idx = parseInt(digitMatch[1], 10) - 1;
            const shiftMod = e.shiftKey && (e.metaKey || e.ctrlKey);
            const altOnly =
                e.altKey && !e.metaKey && !e.ctrlKey && !e.shiftKey;

            if (shiftMod || altOnly) {
                e.preventDefault();
                if (this._searchActive() && idx < MAX_SHORTCUTS) {
                    const row = rows[idx];
                    if (row) {
                        if (shiftMod) this._actOnOrder(row);
                        else this._actOn(row);
                    }
                }
                return;
            }
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
                if (!this.el.isConnected) break;
                try {
                    const view = this.__view();
                    if (!view || !view.isConnected()) break;
                } catch (_) {
                    break;
                }
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

    // Check in every ticket in the order the row belongs to. Falls back to the
    // single-ticket action when the order has no "Check in all" control.
    _actOnOrder(rowEl) {
        const group = rowEl.closest(ORDER_GROUP_SELECTOR);
        const btn = group && group.querySelector(ALL_BTN_SELECTOR);
        if (btn && !btn.disabled) {
            btn.click();
            return;
        }
        this._actOn(rowEl);
    },

    _kbd(label) {
        return `<kbd class="${KBD_CLASS}" style="${KBD_STYLE}">${label}</kbd>`;
    },

    // Populate the per-row (Alt + N) and per-order (Shift+mod + N) shortcut
    // badges. Everything clears when there is no active search.
    _refreshBadges() {
        const rowBadges = Array.from(
            document.querySelectorAll(BADGE_SELECTOR),
        );
        const orderBadges = Array.from(
            document.querySelectorAll(ORDER_BADGE_SELECTOR),
        );

        const clear = (span) => {
            span.innerHTML = "";
            span.setAttribute("hidden", "");
            span.style.display = "";
        };

        if (!this._searchActive()) {
            rowBadges.forEach(clear);
            orderBadges.forEach(clear);
            return;
        }

        const altLabel = altKeyLabel();
        const modLabel = shiftModKeyLabel();

        rowBadges.forEach((span, i) => {
            if (i < MAX_SHORTCUTS) {
                span.style.display = "flex";
                span.innerHTML = this._kbd(altLabel) + this._kbd(i + 1);
                span.removeAttribute("hidden");
            } else {
                clear(span);
            }
        });

        // Order badges: number each multi-ticket group by the position of its
        // first pending row in the full row list, so it lines up with that
        // row's Alt shortcut.
        const rows = this._rows();
        orderBadges.forEach((span) => {
            const group = span.closest(ORDER_GROUP_SELECTOR);
            const firstRow = group && group.querySelector(ROW_SELECTOR);
            const idx = firstRow ? rows.indexOf(firstRow) : -1;

            if (idx >= 0 && idx < MAX_SHORTCUTS) {
                span.style.display = "inline-flex";
                span.innerHTML = this._kbd(modLabel) + this._kbd(idx + 1);
                span.removeAttribute("hidden");
            } else {
                clear(span);
            }
        });
    },
};

export default EventCheckInKeyboard;
