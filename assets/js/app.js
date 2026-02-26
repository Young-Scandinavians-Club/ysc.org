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
import StickyNavbar from "./sticky_navbar";
import Uploaders from "./uploaders";
import BlurHashCanvas from "./blur_hash_canvas";
import BlurHashImage from "./blur_hash_image";
import GrowingInput from "./growing_input_field";
import TrixHook from "./trix_hook";
import DaterangeHover from "./daterange-hover";
import CalendarHover from "./calendar_hover";
import Sortable from "./sortable";
import RadarMap from "./radar";
import MoneyInput from "./money_input";
import Turnstile from "./phoenix_turnstile";
import StripeInput from "./stripe_payment";
import StripeElements from "./stripe_elements";
import CheckoutTimer from "./checkout_timer";
import HoldCountdown from "./hold_countdown";
import CountdownColor from "./countdown_color";
import PanelResizer from "./panel_resizer";
import EmailPreview from "./email_preview";
import AdminSearch from "./admin_search";
import GLightboxHook from "./glightbox_hook";
import LocalTime from "./local_time";
import YearScrubber from "./year_scrubber";
import ScrollPreserver from "./scroll_preserver";
import ResendTimer from "./resend_timer";
import BackToTop from "./back_to_top";
import InfoNav from "./info_nav";
import Confetti from "./confetti";
import AutoConsumeUpload from "./auto_consume_upload";
import ImageCarouselAutoplay from "./image_carousel_autoplay";
import ReadingProgress from "./reading_progress";
import TimelineFilter from "./timeline_filter";
import PathTracker from "./path_tracker";
import Autocomplete from "./autocomplete";
import ReceiptLightbox from "./receipt_lightbox";
import ScrollToSection from "./scroll_to_section";
import PasskeyAuth from "./passkey_auth";
import ConfirmCloseModal from "./confirm_close_modal";
import ClipboardCopy from "./clipboard_copy";
import DecadeIndicator from "./decade_indicator";
import FooterRotator from "./footer_rotator";
import ScrollMoreIndicator from "./scroll_more_indicator";
import { createLiveToastHook } from "../../deps/live_toast";

let Hooks = {
    StickyNavbar,
    BlurHashCanvas,
    BlurHashImage,
    GrowingInput,
    TrixHook,
    DaterangeHover,
    CalendarHover,
    Sortable,
    RadarMap,
    MoneyInput,
    Turnstile,
    StripeInput,
    StripeElements,
    CheckoutTimer,
    HoldCountdown,
    CountdownColor,
    PanelResizer,
    EmailPreview,
    AdminSearch,
    GLightboxHook,
    LocalTime,
    YearScrubber,
    ScrollPreserver,
    ResendTimer,
    BackToTop,
    InfoNav,
    Confetti,
    AutoConsumeUpload,
    ImageCarouselAutoplay,
    ReadingProgress,
    TimelineFilter,
    PathTracker,
    Autocomplete,
    ReceiptLightbox,
    ScrollToSection,
    PasskeyAuth,
    ConfirmCloseModal,
    ClipboardCopy,
    DecadeIndicator,
    FooterRotator,
    ScrollMoreIndicator,
    LiveToast: createLiveToastHook(6000, 3),
};
Hooks.LivePhone = LivePhone;

// Helper function to wait for Sentry to be available with retries
async function waitForSentry(maxAttempts = 5, delayMs = 50) {
    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
        console.log(`waitForSentry: Attempt ${attempt}/${maxAttempts}, window.Sentry =`, window.Sentry);
        if (window.Sentry) {
            console.log("waitForSentry: ✓ Sentry found!");
            return true;
        }
        if (attempt < maxAttempts) {
            await new Promise(resolve => setTimeout(resolve, delayMs));
        }
    }
    console.error("waitForSentry: ✗ Sentry not found after", maxAttempts, "attempts");
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
        
        // Add Replay if available (some bundles include this)
        if (typeof window.Sentry.replayIntegration === 'function') {
            integrations.push(window.Sentry.replayIntegration({
                // Capture 10% of all sessions for replay
                sessionSampleRate: 0.1,
                // Capture 100% of sessions with errors for replay
                errorSampleRate: 1.0,
            }));
        }
        
        window.Sentry.init({
            dsn: "https://9f1197d8becaf697a4ca018daa8c88b5@o4510359659216896.ingest.us.sentry.io/4510359660396544",
            integrations: integrations,
            // Performance Monitoring - capture 10% of transactions
            tracesSampleRate: 0.1,
            // Session Replay (if available in bundle)
            replaysSessionSampleRate: 0.1,
            replaysOnErrorSampleRate: 1.0,
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

        console.log("Sentry initialized successfully with available features:", {
            tracing: typeof window.Sentry.browserTracingIntegration === 'function',
            replay: typeof window.Sentry.replayIntegration === 'function',
            user: !!window.currentUser,
        });
    } else {
        console.warn("Sentry failed to load after multiple attempts - error monitoring will be disabled");
    }
});

let csrfToken = document
    .querySelector("meta[name='csrf-token']")
    .getAttribute("content");

let liveSocket = new LiveSocket("/live", Socket, {
    params: {
        _csrf_token: csrfToken,
        locale: Intl.NumberFormat().resolvedOptions().locale,
        timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
        timezone_offset: -(new Date().getTimezoneOffset() / 60),
    },
    hooks: Hooks,
    uploaders: Uploaders,
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

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" });
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

// Handle custom events from LiveView
window.addEventListener("phx:scroll-to-top", () => {
    setTimeout(() => {
        window.scrollTo({ top: 0, behavior: "smooth" });
    }, 100);
});

window.addEventListener("phx:scroll-to-price-details", () => {
    const priceDetails = document.getElementById("price-details-section");
    if (priceDetails) {
        priceDetails.scrollIntoView({ behavior: "smooth", block: "start" });
        // Also expand if collapsed on mobile
        const toggleButton = priceDetails.querySelector('button[phx-click="toggle-price-details"]');
        if (toggleButton && toggleButton.getAttribute("aria-expanded") !== "true") {
            toggleButton.click();
        }
    }
});

// connect if there are any LiveViews on the page
liveSocket.connect();

// Handle Sentry user context updates when user logs in/out
// LiveView can push this event when authentication state changes
window.addEventListener("phx:update-sentry-user", (e) => {
    const { user } = e.detail || {};
    if (window.Sentry) {
        if (user) {
            window.Sentry.setUser({
                id: user.id,
                email: user.email,
                role: user.role,
                state: user.state,
            });
            window.currentUser = user;
        } else {
            window.Sentry.setUser(null);
            window.currentUser = null;
        }
    } else {
        // Just update the local user reference if Sentry is not available
        window.currentUser = user || null;
    }
});

// Add navigation breadcrumbs to Sentry for error context
window.addEventListener("phx:page-loading-start", (info) => {
    if (window.Sentry) {
        window.Sentry.addBreadcrumb({
            category: "navigation",
            message: "LiveView navigation started",
            level: "info",
        });
    }
});

window.addEventListener("phx:page-loading-stop", (info) => {
    if (window.Sentry) {
        window.Sentry.addBreadcrumb({
            category: "navigation",
            message: "LiveView navigation completed",
            level: "info",
        });
    }
});

// Capture LiveView errors in Sentry
liveSocket.on("phx:error", (error) => {
    if (window.Sentry) {
        window.Sentry.captureException(error);
    }
});

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
            } else {
                input.type = "password";
                icon.classList.remove("hero-eye-slash-solid");
                icon.classList.add("hero-eye-solid");
            }
        }
    }
});

// Handle OTP input functionality
document.addEventListener("input", (event) => {
    if (event.target.matches("[data-otp-input-item]")) {
        const input = event.target;
        const container = input.closest("[data-otp-input]");
        const inputs = container.querySelectorAll("[data-otp-input-item]");
        const index = Array.from(inputs).indexOf(input);

        // If a character was entered and it's not the last input, move to next
        if (input.value && index < inputs.length - 1) {
            inputs[index + 1].focus();
        }
    }
});

document.addEventListener("keydown", (event) => {
    if (event.target.matches("[data-otp-input-item]")) {
        const input = event.target;
        const container = input.closest("[data-otp-input]");
        const inputs = container.querySelectorAll("[data-otp-input-item]");
        const index = Array.from(inputs).indexOf(input);

        // Handle backspace
        if (event.key === "Backspace" && !input.value && index > 0) {
            inputs[index - 1].focus();
        }

        // Handle left arrow
        if (event.key === "ArrowLeft" && index > 0) {
            inputs[index - 1].focus();
        }

        // Handle right arrow
        if (event.key === "ArrowRight" && index < inputs.length - 1) {
            inputs[index + 1].focus();
        }
    }
});

document.addEventListener("paste", (event) => {
    if (event.target.matches("[data-otp-input-item]")) {
        event.preventDefault();
        const paste = event.clipboardData.getData("text").replace(/\s/g, ""); // Remove whitespace
        const container = event.target.closest("[data-otp-input]");
        const inputs = container.querySelectorAll("[data-otp-input-item]");

        // Always start filling from the first input when pasting
        // This ensures the full OTP code is entered correctly regardless of which box has focus
        for (let i = 0; i < paste.length && i < inputs.length; i++) {
            inputs[i].value = paste[i];
            // Trigger input event on each filled input to ensure LiveView picks up the change
            inputs[i].dispatchEvent(new Event("input", { bubbles: true }));
        }

        // Trigger change event on the form to validate the code
        const form = container.closest("form");
        if (form) {
            form.dispatchEvent(new Event("change", { bubbles: true }));
        }

        // Focus the last filled input or the next empty input
        const filledCount = Math.min(paste.length, inputs.length);
        if (filledCount > 0) {
            if (filledCount < inputs.length) {
                inputs[filledCount].focus(); // Focus next empty input
            } else {
                inputs[inputs.length - 1].focus(); // Focus last input if all filled
            }
        }
    }
});

// Auto-submit hook for forms
let AutoSubmit = {
    mounted() {
        this.el.dispatchEvent(new Event("submit", { bubbles: true }));
    },
};

// Add AutoSubmit to hooks
Hooks.AutoSubmit = AutoSubmit;

// Auto-consume uploads when they reach 100% progress
// Listen for multiple possible events
window.addEventListener("phx:file-update", (e) => {
    const { ref, progress } = e.detail || {};
    if (progress === 100) {
        // Find the consume button for this ref
        const consumeButton = document.getElementById(`receipt-consume-${ref}`) ||
            document.getElementById(`proof-consume-${ref}`);
        if (consumeButton && !consumeButton.disabled) {
            // Small delay to ensure upload is fully processed
            setTimeout(() => {
                consumeButton.click();
            }, 200);
        }
    }
});

// Also listen for progress updates via DOM observation
// Check progress bars periodically for completed uploads
setInterval(() => {
    document.querySelectorAll('progress[data-ref]').forEach((progress) => {
        const ref = progress.getAttribute('data-ref');
        const progressValue = parseInt(progress.value) || 0;
        const uploadType = progress.getAttribute('data-upload-type');

        // Check if progress is 100% and button is not disabled
        if (progressValue === 100) {
            const consumeButton = document.getElementById(`${uploadType}-consume-${ref}`);
            if (consumeButton && !consumeButton.disabled && !consumeButton.dataset.consumed) {
                consumeButton.dataset.consumed = 'true';
                setTimeout(() => {
                    consumeButton.click();
                }, 300);
            }
        }
    });
}, 500);

// Handle print-page event for PDF download
window.addEventListener("phx:print-page", () => {
    window.print();
});

// Handle redirect after delay event (for showing success messages before redirect)
window.addEventListener("phx:redirect-after-delay", (e) => {
    const { url, delay = 1500 } = e.detail || {};
    if (url) {
        setTimeout(() => {
            window.location.href = url;
        }, delay);
    }
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