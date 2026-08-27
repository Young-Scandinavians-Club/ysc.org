// Returns platform-appropriate key labels for modifier keys.
// Used to show ⌥ on Mac and "alt" on Windows/Linux.

export function isMac() {
    // navigator.userAgentData is the modern API; fall back to userAgent string.
    if (navigator.userAgentData?.platform) {
        return navigator.userAgentData.platform === "macOS";
    }
    return /Mac|iPhone|iPod|iPad/.test(navigator.platform);
}

export function altKeyLabel() {
    return isMac() ? "⌥" : "alt";
}

// Label for the "check in whole order" chord: Shift+Cmd on Mac, Shift+Ctrl elsewhere.
export function shiftModKeyLabel() {
    return isMac() ? "⇧⌘" : "⇧ ctrl";
}

// Update all <kbd data-key="…"> elements in the DOM with the correct platform label.
// Call once after the page is interactive.
export function applyPlatformKeyLabels() {
    const labels = {
        alt: altKeyLabel(),
        "shift-mod": shiftModKeyLabel(),
    };
    Object.entries(labels).forEach(([key, label]) => {
        document.querySelectorAll(`kbd[data-key='${key}']`).forEach((el) => {
            el.textContent = label;
        });
    });
}
