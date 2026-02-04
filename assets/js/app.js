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
import HistoryNav from "./history_nav";
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
    HistoryNav,
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
};
Hooks.LivePhone = LivePhone;

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
        const paste = event.clipboardData.getData("text");
        const container = event.target.closest("[data-otp-input]");
        const inputs = container.querySelectorAll("[data-otp-input-item]");
        const index = Array.from(inputs).indexOf(event.target);

        // Fill inputs with pasted content
        for (let i = 0; i < paste.length && index + i < inputs.length; i++) {
            inputs[index + i].value = paste[i];
            // Trigger input event on each filled input to ensure LiveView picks up the change
            inputs[index + i].dispatchEvent(new Event("input", { bubbles: true }));
        }

        // Trigger change event on the form to validate the code
        const form = container.closest("form");
        if (form) {
            form.dispatchEvent(new Event("change", { bubbles: true }));
        }

        // Focus the next empty input or the last input
        const nextEmptyIndex = Array.from(inputs).findIndex((input, i) => i > index && !input.value);
        if (nextEmptyIndex !== -1) {
            inputs[nextEmptyIndex].focus();
        } else {
            inputs[Math.min(index + paste.length, inputs.length - 1)].focus();
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
    console.log("phx:file-update event:", e.detail);
    const { ref, progress } = e.detail || {};
    if (progress === 100) {
        // Find the consume button for this ref
        const consumeButton = document.getElementById(`receipt-consume-${ref}`) ||
            document.getElementById(`proof-consume-${ref}`);
        if (consumeButton && !consumeButton.disabled) {
            console.log("Auto-consuming upload:", ref);
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
                console.log("Auto-consuming upload via progress check:", ref, "progress:", progressValue);
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