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

// Update all <kbd data-key="alt"> elements in the DOM with the correct label.
// Call once after the page is interactive.
export function applyPlatformKeyLabels() {
    const label = altKeyLabel();
    document.querySelectorAll("kbd[data-key='alt']").forEach((el) => {
        el.textContent = label;
    });
}
