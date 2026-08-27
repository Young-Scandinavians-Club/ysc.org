// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Sentry is loaded via a script tag in root.html.heex to ensure window.Sentry is available
// before this bundle executes. See priv/static/assets/sentry.min.js

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html";
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "../vendor/topbar";
import "../vendor/add-to-calendar-button@2.js";
import LivePhone from "./live_phone";
import StickyNavbar, { syncNavHeight } from "./sticky_navbar";
import { releaseStaleBodyScrollLock, shouldReleaseScrollLockOnNavigation } from "./body_scroll_lock";
import Uploaders from "./uploaders";
import BlurHashCanvas from "./blur_hash_canvas";
import BlurHashImage from "./blur_hash_image";
import DaterangeHover from "./daterange-hover";
import RadarMap from "./radar";
import RadarLocationAutocomplete from "./radar_location_autocomplete";
import MoneyInput from "./money_input";
import Turnstile from "./phoenix_turnstile";
import StripeInput from "./stripe_payment";
import StripeElements from "./stripe_elements";
import Countdown from "./countdown";
import GLightboxHook from "./glightbox_hook";
import LocalTime from "./local_time";
import ResendTimer from "./resend_timer";
import BackToTop from "./back_to_top";
import Confetti from "./confetti";
import AutoConsumeUpload from "./auto_consume_upload";
import ImageCarouselAutoplay from "./image_carousel_autoplay";
import ReadingProgress from "./reading_progress";
import TimelineFilter from "./timeline_filter";
import ReceiptLightbox from "./receipt_lightbox";
import ScrollToSection from "./scroll_to_section";
import PasskeyAuth from "./passkey_auth";
import ConfirmCloseModal from "./confirm_close_modal";
import FooterRotator from "./footer_rotator";
import HeroVideoControls from "./hero_video_controls";
import HeroFlagGrid from "./hero_flag_grid";
import AdminFloatingButton from "./admin_floating_button";
import AutoResizeIframe from "./auto_resize_iframe";
import AutoResizeTextarea from "./auto_resize_textarea";
import AgendaTracksScroller from "./agenda_tracks_scroller";
import TicketSlider from "./ticket_slider";
import TicketCheckout from "./ticket_checkout";
import WalletPlatform, { detectWalletPlatform } from "./wallet_platform";
import AvatarCropper from "./avatar_cropper";
import { createLiveToastHook } from "../vendor/live_toast.esm.js";
import { ToastFlashBridge } from "./toast_flash_bridge";
import InteractScrollbar from "./interact_scrollbar";
import OtpInput from "./otp_input";
import StopClick from "./stop_click";

// Duration (ms) and max toasts per LiveToast docs: https://hexdocs.pm/live_toast/readme.html
const TOAST_DURATION_MS = 6000;
const MAX_TOAST_ITEMS = 3;

let Hooks = {
    StickyNavbar,
    BlurHashCanvas,
    BlurHashImage,
    DaterangeHover,
    RadarMap,
    RadarLocationAutocomplete,
    MoneyInput,
    Turnstile,
    StripeInput,
    StripeElements,
    Countdown,
    GLightboxHook,
    LocalTime,
    ResendTimer,
    BackToTop,
    Confetti,
    AutoConsumeUpload,
    ImageCarouselAutoplay,
    ReadingProgress,
    TimelineFilter,
    ReceiptLightbox,
    ScrollToSection,
    PasskeyAuth,
    ConfirmCloseModal,
    FooterRotator,
    HeroVideoControls,
    HeroFlagGrid,
    AdminFloatingButton,
    AutoResizeIframe,
    AutoResizeTextarea,
    AgendaTracksScroller,
    TicketSlider,
    TicketCheckout,
    WalletPlatform,
    AvatarCropper,
    InteractScrollbar,
    OtpInput,
    StopClick,
    LiveToast: createLiveToastHook(TOAST_DURATION_MS, MAX_TOAST_ITEMS),
    ToastFlashBridge,
};
Hooks.LivePhone = LivePhone;

// Merge any admin-only hooks registered by admin.js (loaded before this bundle on admin pages)
Object.assign(Hooks, window.__adminHooks || {});

// Helper function to wait for Sentry to be available with retries
async function waitForSentry(maxAttempts = 5, delayMs = 50) {
    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
        if (window.Sentry) return true;
        if (attempt < maxAttempts) {
            await new Promise(resolve => setTimeout(resolve, delayMs));
        }
    }
    console.warn("waitForSentry: Sentry not found after", maxAttempts, "attempts — error monitoring disabled");
    return false;
}

// Initialize Sentry for JavaScript error monitoring
// This must happen before LiveSocket is created to capture all errors
// The Sentry bundle exposes a global window.Sentry object
waitForSentry().then((available) => {
    if (available) {
        // Build integrations array - only include available integrations
        const integrations = [];

        // Add BrowserTracing if available (Performance Bundle includes this)
        if (typeof window.Sentry.browserTracingIntegration === 'function') {
            integrations.push(window.Sentry.browserTracingIntegration({
                // Track LiveView navigation as transactions
                tracePropagationTargets: ["localhost", /^\//],
            }));
        }

        window.Sentry.init({
            dsn: "https://9f1197d8becaf697a4ca018daa8c88b5@o4510359659216896.ingest.us.sentry.io/4510359660396544",
            environment: document.documentElement.dataset.appEnv || "production",
            integrations: integrations,
            // Performance Monitoring - capture 10% of transactions
            tracesSampleRate: 0.1,
            // Discoverable-credential unsupported on some Chrome/platform setups (WebAuthn)
            ignoreErrors: [
                /Resident credentials or empty 'allowCredentials' lists are not supported/,
            ],
            beforeSend(event) {
                if (isExpectedWebAuthnOrVideoNotAllowed(event)) {
                    return null;
                }
                return event;
            },
        });

        // Set user context if user is logged in
        if (window.currentUser) {
            window.Sentry.setUser({
                id: window.currentUser.id,
                email: window.currentUser.email,
                role: window.currentUser.role,
                state: window.currentUser.state,
            });
        } else {
            // Clear user context for anonymous users
            window.Sentry.setUser(null);
        }

    } else {
        console.warn("Sentry failed to load after multiple attempts - error monitoring will be disabled");
    }
});

// Ignore NotAllowedError only when it comes from WebAuthn or media playback — keep
// other permission denials (geolocation, notifications, clipboard, etc.) visible.
function isExpectedWebAuthnOrVideoNotAllowed(event) {
    const exceptions = event?.exception?.values || [];

    return exceptions.some((ex) => {
        const type = ex.type || "";
        const value = ex.value || "";
        const isNotAllowed =
            type === "NotAllowedError" ||
            value.startsWith("NotAllowedError") ||
            /not allowed by the user agent or the platform/i.test(value);

        if (!isNotAllowed) return false;

        const frames = ex.stacktrace?.frames || [];
        return frames.some((frame) => {
            const haystack = `${frame.function || ""} ${frame.filename || ""} ${frame.abs_path || ""}`;
            return /(?:^|\W)play(?:\W|$)|HTMLVideoElement|hero_video|passkey|credentials\.(?:get|create)|WebAuthn|PublicKeyCredential/i.test(
                haystack
            );
        });
    });
}

let csrfToken = document
    .querySelector("meta[name='csrf-token']")
    .getAttribute("content");

let liveSocket = new LiveSocket("/live", Socket, {
    params: () => ({
        _csrf_token: csrfToken,
        locale: Intl.NumberFormat().resolvedOptions().locale,
        timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
        timezone_offset: -(new Date().getTimezoneOffset() / 60),
        sidebar_collapsed: localStorage.getItem("admin-sidebar-collapsed") === "true",
        // Cached wallet platform so the server knows the correct value from the
        // very first connected render (eliminates layout shifts on return visits).
        // Each step (localStorage read, live detection) is isolated in its own
        // try/catch so neither can propagate an exception that aborts LiveSocket.
        wallet_platform: (() => {
            try {
                const cached = localStorage.getItem("wallet_platform");
                if (cached) return cached;
            } catch (_) {}
            try {
                return detectWalletPlatform();
            } catch (_) {
                return "both";
            }
        })(),
    }),
    hooks: Hooks,
    uploaders: Uploaders,
    // Delay before showing "Attempting to reconnect" so short connection blips don't flash the message.
    // If the socket reconnects within this window, the message is never shown and the timer is cleared.
    disconnectedTimeout: 1000,
});

window.addEventListener("phx:live_reload:attached", ({ detail: reloader }) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs();
    window.liveReloader = reloader;
});

// Disable browser's automatic scroll restoration for better control
if ('scrollRestoration' in history) {
    history.scrollRestoration = 'manual';
}

function maybeReleaseStaleBodyScrollLock(detail) {
    if (shouldReleaseScrollLockOnNavigation(detail)) {
        releaseStaleBodyScrollLock();
    }
}

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" });
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (event) => {
    topbar.hide();
    maybeReleaseStaleBodyScrollLock(event.detail);
});
window.addEventListener("phx:navigate", (event) => {
    maybeReleaseStaleBodyScrollLock(event.detail);
});

// Handle custom events from LiveView
window.addEventListener("phx:scroll-to-top", () => {
    setTimeout(() => {
        window.scrollTo({ top: 0, behavior: "smooth" });
    }, 100);
});

window.addEventListener("phx:focus-first-input", (e) => {
    setTimeout(() => {
        const container = document.getElementById(e.detail.id);
        if (!container) return;
        const input = container.querySelector(
            'input:not([type="hidden"]):not([type="checkbox"]), select, textarea'
        );
        if (input) input.focus();
    }, 150);
});

// Measure navbar before LiveView connects so the spacer matches on first paint.
syncNavHeight();
if (document.fonts?.ready) {
    document.fonts.ready.then(syncNavHeight);
}

// connect if there are any LiveViews on the page
liveSocket.connect();

// Mobile browsers suspend JS timers (including the LiveView heartbeat) while a tab
// or app is backgrounded, which can leave the socket stuck in a stale state that
// the default heartbeat/backoff timers never recover from on their own.
//
// Gating the forced reconnect on `liveSocket.isConnected()` (as this used to do,
// and as Phoenix's own built-in visibilitychange handler in phoenix.js still
// does) doesn't work here: isConnected() just reflects the raw WebSocket's
// readyState, and on iOS Safari and several Android browsers that readyState
// keeps reporting "open" for a connection that's actually dead, because the
// close/error event is never delivered while the tab is suspended in the
// background. That's why the banner could still hang forever after this
// "fix" shipped in #1104 — the condition guarding the reconnect was exactly
// the signal that's unreliable in this scenario.
//
// Instead, track how long the page was hidden and force a fresh teardown +
// reconnect unconditionally once we've been hidden long enough for the
// connection to plausibly have gone stale, regardless of what isConnected()
// reports. Reconnecting when the socket was actually still healthy just
// causes a quick, harmless rejoin.
//
// Chrome 149+ (and installed PWAs) can skip `visibilitychange` after a freeze;
// the Page Lifecycle `resume` event still fires. Phoenix 1.8.13 listens for
// that too — keep this more aggressive reconnect on the same path.
const STALE_AFTER_HIDDEN_MS = 3000;
let hiddenAt = null;

function markPageHidden() {
    if (hiddenAt === null) {
        hiddenAt = Date.now();
    }
}

function reconnectIfStaleAfterHidden() {
    if (hiddenAt !== null && Date.now() - hiddenAt > STALE_AFTER_HIDDEN_MS) {
        liveSocket.disconnect(() => liveSocket.connect());
    }
    hiddenAt = null;
}

document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "hidden") {
        markPageHidden();
        return;
    }

    reconnectIfStaleAfterHidden();
});

document.addEventListener("freeze", markPageHidden);
document.addEventListener("resume", reconnectIfStaleAfterHidden);

// Handle map toggle text updates
window.addEventListener("phx:toggle-map-text", () => {
    const buttonText = document.getElementById("map-button-text");
    const mapElement = document.getElementById("event-map");

    if (buttonText && mapElement) {
        if (!mapElement.classList.contains("hidden")) {
            buttonText.textContent = "Show Map";
        } else {
            buttonText.textContent = "Hide Map";
        }
    }
});

// Handle CSV download
window.addEventListener("phx:download-csv", (e) => {
    const { content, filename } = e.detail;

    // Decode base64 content
    const binaryString = atob(content);
    const bytes = new Uint8Array(binaryString.length);
    for (let i = 0; i < binaryString.length; i++) {
        bytes[i] = binaryString.charCodeAt(i);
    }

    // Create blob and download
    const blob = new Blob([bytes], { type: "text/csv;charset=utf-8;" });
    const url = window.URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = filename;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    window.URL.revokeObjectURL(url);
});

// Handle ticket availability updates animation
window.addEventListener("phx:animate-availability-update", () => {
    // Find all tier availability elements and add animation class
    const availabilityElements = document.querySelectorAll('[id^="tier-availability-"]');
    availabilityElements.forEach((el) => {
        // Remove the class first to reset animation
        el.classList.remove("availability-updated");
        // Force reflow to ensure the class removal is processed
        void el.offsetWidth;
        // Add the class to trigger animation
        el.classList.add("availability-updated");
        // Remove the class after animation completes
        setTimeout(() => {
            el.classList.remove("availability-updated");
        }, 600);
    });
});

// Handle password visibility toggle
document.addEventListener("click", (event) => {
    if (event.target.closest(".password-toggle-btn")) {
        const button = event.target.closest(".password-toggle-btn");
        const targetId = button.getAttribute("data-target");
        const input = document.querySelector(targetId);
        const icon = button.querySelector('.h-5.w-5');

        if (input && icon) {
            if (input.type === "password") {
                input.type = "text";
                icon.classList.remove("hero-eye-solid");
                icon.classList.add("hero-eye-slash-solid");
                button.setAttribute("aria-label", "Hide password");
                button.setAttribute("aria-pressed", "true");
            } else {
                input.type = "password";
                icon.classList.remove("hero-eye-slash-solid");
                icon.classList.add("hero-eye-solid");
                button.setAttribute("aria-label", "Show password");
                button.setAttribute("aria-pressed", "false");
            }
        }
    }
});

// Handle print-page event for PDF download (optional detail.title for the saved PDF name)
window.addEventListener("phx:print-page", (event) => {
    const title = event.detail?.title;

    if (!title) {
        window.print();
        return;
    }

    const previousTitle = document.title;
    document.title = title;

    const restoreTitle = () => {
        document.title = previousTitle;
        window.removeEventListener("afterprint", restoreTitle);
    };

    window.addEventListener("afterprint", restoreTitle);
    window.print();
});

// Handle copy to clipboard for Report ID
document.addEventListener("click", (event) => {
    if (event.target.closest('[phx-click="copy-report-id"]')) {
        const button = event.target.closest('[phx-click="copy-report-id"]');
        const reportId = button.getAttribute('phx-value-id');
        if (reportId) {
            navigator.clipboard.writeText(reportId).then(() => {
                // Flash message will be shown by LiveView
            }).catch((err) => {
                console.error('Failed to copy:', err);
            });
        }
    }
});

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket;