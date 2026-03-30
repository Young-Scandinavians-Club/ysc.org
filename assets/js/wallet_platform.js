// Detects the user's platform and pushes a wallet_platform_detected event so the
// server can show only the relevant "Add to Wallet" button(s).
//
// Rules:
//   iOS (iPhone / iPad / iPod)  → apple_only
//   Mac + Safari                → apple_only  (Apple Wallet web API works here)
//   Android                     → google_only
//   Everything else             → both
//
// The detected value is cached in localStorage under STORAGE_KEY and also read
// back by the LiveSocket connect params (see app.js) so the server knows the
// correct platform from the very first connected render, eliminating layout shifts
// on all visits after the first.

const STORAGE_KEY = "wallet_platform";

export function detectWalletPlatform() {
    const ua = navigator.userAgent;

    const isIOS = /iPhone|iPad|iPod/.test(ua);
    const isAndroid = /Android/.test(ua);
    // Distinguish Mac from iOS (some iPads send "Macintosh" in their UA)
    const isMac = /Macintosh|Mac OS X/.test(ua) && !isIOS;
    // Safari but not Chrome, Edge, or other Chromium-based browsers
    const isSafari = /Safari/.test(ua) && !/Chrome|CriOS|FxiOS|Chromium|OPR|Edg/.test(ua);
    const isMacSafari = isMac && isSafari;

    if (isIOS || isMacSafari) return "apple_only";
    if (isAndroid) return "google_only";
    return "both";
}

const WalletPlatform = {
    mounted() {
        const platform = detectWalletPlatform();

        // Persist so app.js can include it in connect_params on the next page load,
        // letting the server set the correct initial assign before the first DOM patch.
        try {
            localStorage.setItem(STORAGE_KEY, platform);
        } catch (_) {
            // localStorage may be unavailable in private browsing or sandboxed contexts
        }

        this.pushEvent("wallet_platform_detected", { platform });
    }
};

export default WalletPlatform;
