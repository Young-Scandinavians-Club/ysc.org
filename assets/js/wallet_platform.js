// Detects the user's platform and pushes a wallet_platform_detected event so the
// server can show only the relevant "Add to Wallet" button(s).
//
// Rules:
//   iOS (iPhone / iPad / iPod)  → apple_only
//   Mac + Safari                → apple_only  (Apple Wallet web API works here)
//   Android                     → google_only
//   Everything else             → both
const WalletPlatform = {
    mounted() {
        const ua = navigator.userAgent;

        const isIOS = /iPhone|iPad|iPod/.test(ua);
        const isAndroid = /Android/.test(ua);
        // Distinguish Mac from iOS (iPads send "Mac" in some UAs)
        const isMac = /Macintosh|Mac OS X/.test(ua) && !isIOS;
        // Safari but not Chrome, Edge, or other Chromium-based browsers
        const isSafari = /Safari/.test(ua) && !/Chrome|CriOS|FxiOS|Chromium|OPR|Edg/.test(ua);
        const isMacSafari = isMac && isSafari;

        let platform;
        if (isIOS || isMacSafari) {
            platform = "apple_only";
        } else if (isAndroid) {
            platform = "google_only";
        } else {
            platform = "both";
        }

        this.pushEvent("wallet_platform_detected", { platform });
    }
};

export default WalletPlatform;
