// html5-qrcode is loaded via a standalone <script> tag in admin_root.html.heex
// so its UMD wrapper correctly sets window.Html5Qrcode in the global scope.
// Do NOT import it here — esbuild bundling breaks the UMD global assignment.

const SCAN_COOLDOWN_MS = 3000;

function getHtml5Qrcode() {
  if (window.__Html5QrcodeLibrary__) {
    return window.__Html5QrcodeLibrary__.Html5Qrcode;
  }
  if (window.Html5Qrcode) {
    return window.Html5Qrcode;
  }
  return null;
}

export default {
  safePush(event, payload) {
    if (this.isDestroyed || !this.el?.isConnected) return;
    try {
      const view = this.__view();
      if (!view || !view.isConnected()) return;
    } catch (_) {
      return;
    }
    this.pushEvent(event, payload);
  },

  mounted() {
    this.scanner = null;
    this.cooldown = false;
    this.cameraActive = false;
    this.cameraStarting = false;
    this.isDestroyed = false;
    this.stopRequested = false;

    this.log("hook mounted");

    // Register server-driven events (for future use / manual retries)
    this.handleEvent("start-camera", () => {
      this.log("received start-camera event from server");
      this.startCamera();
    });
    this.handleEvent("stop-camera", () => {
      this.log("received stop-camera event from server");
      this.stopCamera();
    });

    const overlay = this.el.querySelector("#reconnecting-overlay");
    if (overlay) {
      this.onPageLoadingStart = (info) => {
        if (info.detail?.kind === "error") {
          overlay.classList.remove("hidden");
          overlay.classList.add("flex");
        }
      };
      this.onPageLoadingStop = () => {
        overlay.classList.add("hidden");
        overlay.classList.remove("flex");
      };

      window.addEventListener("phx:page-loading-start", this.onPageLoadingStart);
      window.addEventListener("phx:page-loading-stop", this.onPageLoadingStop);
    }

    // Auto-start: the hook element is only rendered during :scanning phase,
    // so mounting always means we should start the camera immediately.
    this.startCamera();
  },

  log(message, extra) {
    console.log("[QrScanner]", message, extra || "");
    this.safePush("scanner_debug", { message, extra: extra || null });
  },

  async startCamera() {
    if (this.cameraActive || this.cameraStarting || this.isDestroyed) {
      return;
    }

    this.cameraStarting = true;

    this.log("startCamera called", {
      isSecureContext: window.isSecureContext,
      protocol: window.location.protocol,
      hasMediaDevices: !!navigator.mediaDevices,
      userAgent: navigator.userAgent,
    });

    // Check secure context — camera API requires HTTPS (or localhost)
    if (!window.isSecureContext) {
      const reason =
        "Camera requires a secure connection (HTTPS). " +
        "Current protocol: " + window.location.protocol;
      this.log("insecure context", { protocol: window.location.protocol });
      this.safePush("camera_error", { reason });
      this.cameraStarting = false;
      return;
    }

    // Check mediaDevices API availability
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      const reason = "Camera API (mediaDevices) not available in this browser.";
      this.log("mediaDevices unavailable");
      this.safePush("camera_error", { reason });
      this.cameraStarting = false;
      return;
    }

    // Explicitly request camera permission first — this triggers the browser prompt
    this.log("requesting camera permission via getUserMedia");
    let permissionStream;
    try {
      permissionStream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: "environment" },
      });
      this.log("camera permission granted");
      // Stop the probe stream immediately; html5-qrcode will open its own
      permissionStream.getTracks().forEach((t) => t.stop());
    } catch (err) {
      const reason = "Camera permission denied or unavailable: " + err.message;
      this.log("camera permission error", {
        name: err.name,
        message: err.message,
      });
      this.safePush("camera_error", { reason });
      this.cameraStarting = false;
      return;
    }

    if (this.isDestroyed) {
      this.cameraStarting = false;
      return;
    }

    const readerEl = this.el.querySelector("[data-qr-reader]");
    if (!readerEl) {
      const reason = "QR reader DOM element not found.";
      this.log("reader element missing");
      this.safePush("camera_error", { reason });
      this.cameraStarting = false;
      return;
    }

    const Html5QrcodeClass = getHtml5Qrcode();
    if (!Html5QrcodeClass) {
      const reason =
        "html5-qrcode library did not load. " +
        "window.Html5Qrcode=" + typeof window.Html5Qrcode + ", " +
        "window.__Html5QrcodeLibrary__=" + typeof window.__Html5QrcodeLibrary__;
      this.log("library not found", {
        Html5Qrcode: typeof window.Html5Qrcode,
        __Html5QrcodeLibrary__: typeof window.__Html5QrcodeLibrary__,
      });
      this.safePush("camera_error", { reason });
      this.cameraStarting = false;
      return;
    }

    this.log("creating Html5Qrcode instance", { elementId: readerEl.id });
    this.scanner ??= new Html5QrcodeClass(readerEl.id);

    this.log("calling scanner.start()");
    this.scanner
      .start(
        { facingMode: "environment" },
        { fps: 10, qrbox: { width: 250, height: 250 }, aspectRatio: 1.0 },
        (decodedText) => {
          if (this.cooldown) return;
          this.cooldown = true;
          this.log("QR code decoded", { length: decodedText.length });
          this.safePush("scan_result", { data: decodedText });
          setTimeout(() => {
            this.cooldown = false;
          }, SCAN_COOLDOWN_MS);
        },
        (_errorMessage) => {
          // Per-frame decode failures are normal; suppress to avoid noise
        }
      )
      .then(() => {
        if (this.isDestroyed || this.stopRequested) {
          this.stopRequested = false;
          return this.scanner?.stop().then(() => {
            this.cameraActive = false;
            this.scanner = null;
          });
        }
        this.cameraActive = true;
        this.log("camera started successfully");
        this.safePush("camera_started", {});
      })
      .catch((err) => {
        this.scanner = null;
        const reason = "Scanner start failed: " + err.toString();
        this.log("scanner.start() failed", {
          error: err.toString(),
          name: err.name,
        });
        this.safePush("camera_error", { reason });
      })
      .finally(() => {
        this.cameraStarting = false;
      });
  },

  stopCamera() {
    this.log("stopCamera called", { cameraActive: this.cameraActive, cameraStarting: this.cameraStarting });
    if (this.cameraStarting) {
      this.stopRequested = true;
      return;
    }
    if (this.scanner && this.cameraActive) {
      this.scanner
        .stop()
        .then(() => {
          this.cameraActive = false;
          this.scanner = null;
          this.log("camera stopped");
        })
        .catch((err) => {
          this.log("stopCamera error", { error: err.toString() });
        });
    }
  },

  destroyed() {
    this.isDestroyed = true;
    this.log("hook destroyed");

    if (this.onPageLoadingStart) {
      window.removeEventListener("phx:page-loading-start", this.onPageLoadingStart);
    }
    if (this.onPageLoadingStop) {
      window.removeEventListener("phx:page-loading-stop", this.onPageLoadingStop);
    }

    this.stopCamera();
  },
};
