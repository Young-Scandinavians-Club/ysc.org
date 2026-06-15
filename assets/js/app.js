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
import AdminFloatingButton from "./admin_floating_button";
import AutoResizeIframe from "./auto_resize_iframe";
import AutoResizeTextarea from "./auto_resize_textarea";
import AgendaTracksScroller from "./agenda_tracks_scroller";
import TicketSlider from "./ticket_slider";
import WalletPlatform, { detectWalletPlatform } from "./wallet_platform";
import AvatarCropper from "./avatar_cropper";
import { createLiveToastHook } from "../vendor/live_toast.esm.js";

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
    AdminFloatingButton,
    AutoResizeIframe,
    AutoResizeTextarea,
    AgendaTracksScroller,
    TicketSlider,
    WalletPlatform,
    AvatarCropper,
    LiveToast: createLiveToastHook(TOAST_DURATION_MS, MAX_TOAST_ITEMS),
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
            integrations: integrations,
            // Performance Monitoring - capture 10% of transactions
            tracesSampleRate: 0.1,
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
        const filledCount = Math.min(paste.length, inputs.length);

        for (let i = 0; i < filledCount; i++) {
            inputs[i].value = paste[i];
            // Trigger input event on each filled input to ensure LiveView picks up the change
            inputs[i].dispatchEvent(new Event("input", { bubbles: true }));
        }

        for (let i = filledCount; i < inputs.length; i++) {
            inputs[i].value = "";
            inputs[i].dispatchEvent(new Event("input", { bubbles: true }));
        }

        // Trigger change on the last filled input so phx-change validates the code.
        // Do not dispatch change on the form element itself — LiveView pushInput
        // requires a form control (input.form), and HTMLFormElement has no .form.
        if (filledCount > 0) {
            inputs[filledCount - 1].dispatchEvent(new Event("change", { bubbles: true }));

            if (filledCount < inputs.length) {
                inputs[filledCount].focus(); // Focus next empty input
            } else {
                inputs[filledCount - 1].focus(); // Focus last input if all filled
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