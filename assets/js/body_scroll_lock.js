/** Mobile nav toggle id from `app.html.heex` (`toggle_id="navbar-dropdown"`). */
export const MOBILE_MENU_TOGGLE_ID = "navbar-dropdown";

/** Resets the slide-in mobile menu to its closed server-rendered state. */
export function resetMobileMenu(toggleId = MOBILE_MENU_TOGGLE_ID) {
    const overlay = document.getElementById(`${toggleId}-overlay`);
    const panel = document.getElementById(toggleId);
    const hamburger = document.getElementById(`${toggleId}-hamburger`);

    overlay?.classList.add("hidden");
    panel?.classList.add("-translate-x-full");
    panel?.classList.remove("translate-x-0");
    hamburger?.classList.remove("open");
}

function hasVisibleModal() {
    return Array.from(document.querySelectorAll("[phx-remove]")).some(
        (el) =>
            el.querySelector('[role="dialog"][aria-modal="true"]') &&
            !el.classList.contains("hidden"),
    );
}

/**
 * Clears stale `body.overflow-hidden` left behind when LiveView navigates away
 * while the mobile menu or a destroyed modal had scroll lock enabled. `<body>`
 * sits outside the LiveView tree, so those classes are not reset on navigation.
 */
export function releaseStaleBodyScrollLock() {
    resetMobileMenu();

    if (!hasVisibleModal()) {
        document.body.classList.remove("overflow-hidden");
    }
}
