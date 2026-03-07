// Admin-only JavaScript bundle
// Loaded exclusively on admin pages via admin_root.html.heex, listed before app.js so that
// window.__adminHooks is populated before app.js reads it during LiveSocket setup.
import TrixHook from "./trix_hook";
import Sortable from "./sortable";

window.__adminHooks = { TrixHook, Sortable };
