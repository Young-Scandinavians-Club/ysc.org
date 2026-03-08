// Admin-only JavaScript bundle
// Loaded exclusively on admin pages via admin_root.html.heex, listed before app.js so that
// window.__adminHooks is populated before app.js reads it during LiveSocket setup.
import TrixHook from "./trix_hook";
import Sortable from "./sortable";
import AdminSearch from "./admin_search";
import EmailPreview from "./email_preview";
import PanelResizer from "./panel_resizer";
import YearScrubber from "./year_scrubber";
import ScrollMoreIndicator from "./scroll_more_indicator";
import CalendarHover from "./calendar_hover";
import ScrollPreserver from "./scroll_preserver";
import Autocomplete from "./autocomplete";
import ClipboardCopy from "./clipboard_copy";
import GrowingInput from "./growing_input_field";
import FocusSearchInput from "./focus_search_input";

window.__adminHooks = {
    TrixHook,
    Sortable,
    AdminSearch,
    EmailPreview,
    PanelResizer,
    YearScrubber,
    ScrollMoreIndicator,
    CalendarHover,
    ScrollPreserver,
    Autocomplete,
    ClipboardCopy,
    GrowingInput,
    FocusSearchInput,
};

window.addEventListener("phx:focus-search", (e) => {
    const targetId = e.detail?.id;
    if (!targetId) return;
    const tryFocus = (attempt = 0) => {
        const el = document.getElementById(targetId);
        if (el) {
            el.focus();
            return;
        }
        if (attempt < 20) {
            setTimeout(() => tryFocus(attempt + 1), 50);
        }
    };
    requestAnimationFrame(() => {
        setTimeout(() => tryFocus(0), 50);
    });
});
