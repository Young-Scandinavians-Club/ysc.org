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
import ScheduleTimezone from "./schedule_timezone";
import LocalTime from "./local_time";
import QrScanner from "./qr_scanner";
import StickyEventHeader from "./sticky_event_header";
import MembershipCheckInKeyboard from "./membership_checkin_keyboard";
import EventCheckInKeyboard from "./event_checkin_keyboard";
import MediaDropZone from "./media_drop_zone";
import { applyPlatformKeyLabels } from "./platform_keys";

const SIDEBAR_STORAGE_KEY = "admin-sidebar-collapsed";
const SIDEBAR_COOKIE_NAME = "admin_sb_collapsed";

// Called by the sidebar toggle button via JS.dispatch("admin:toggle-sidebar").
// Updates localStorage (for the inline-script no-flash on hard reload), sets a
// plain cookie so the server can render the correct class on each LiveView
// navigation, and immediately toggles the class for instant visual feedback.
document.addEventListener("admin:toggle-sidebar", () => {
    const isCollapsed = !document.documentElement.classList.contains("sidebar-collapsed");
    localStorage.setItem(SIDEBAR_STORAGE_KEY, isCollapsed ? "true" : "false");
    document.cookie = `${SIDEBAR_COOKIE_NAME}=${isCollapsed ? "1" : "0"}; path=/; max-age=31536000; SameSite=Lax`;
    document.documentElement.classList.toggle("sidebar-collapsed", isCollapsed);
});

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
    ScheduleTimezone,
    LocalTime,
    QrScanner,
    StickyEventHeader,
    MembershipCheckInKeyboard,
    EventCheckInKeyboard,
    MediaDropZone,
};

// Apply platform-aware key labels on initial load and after every LiveView patch.
window.addEventListener("DOMContentLoaded", applyPlatformKeyLabels);
window.addEventListener("phx:page-loading-stop", applyPlatformKeyLabels);

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

window.addEventListener("phx:focus-and-clear", (e) => {
    const targetId = e.detail?.id;
    if (!targetId) return;
    const tryFocusAndClear = (attempt = 0) => {
        const el = document.getElementById(targetId);
        if (el) {
            el.value = "";
            el.focus();
            return;
        }
        if (attempt < 20) {
            setTimeout(() => tryFocusAndClear(attempt + 1), 50);
        }
    };
    requestAnimationFrame(() => tryFocusAndClear(0));
});
