import Cropper from "../vendor/cropper.js";

const MAX_POLL_ATTEMPTS = 50;
const POLL_INTERVAL_MS = 300;
const SUBMIT_DELAY_MS = 500;

const AvatarCropper = {
  mounted() {
    this.cropperInstance = null;
    this.pollTimer = null;

    const fileInput = this.el.querySelector("[data-avatar-file-input]");
    if (fileInput) {
      fileInput.addEventListener("change", (e) => this.handleFileSelect(e));
    }

    const confirmBtn = this.el.querySelector("[data-cropper-confirm]");
    if (confirmBtn) {
      confirmBtn.addEventListener("click", () => this.confirmCrop());
    }

    const cancelBtn = this.el.querySelector("[data-cropper-cancel]");
    if (cancelBtn) {
      cancelBtn.addEventListener("click", () => this.cancelCrop());
    }
  },

  getLiveInput() {
    return this.el.querySelector("[data-phx-upload-ref]");
  },

  getFileInput() {
    return this.el.querySelector("[data-avatar-file-input]");
  },

  getCropperContainer() {
    return this.el.querySelector("[data-cropper-container]");
  },

  getCropperModal() {
    return this.el.querySelector("[data-cropper-modal]");
  },

  destroyed() {
    this.destroyCropper();
    this.stopPolling();
  },

  handleFileSelect(e) {
    const file = e.target.files[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = (event) => {
      this.destroyCropper();

      const container = this.getCropperContainer();
      if (!container) return;
      container.innerHTML = "";

      const img = document.createElement("img");
      img.src = event.target.result;
      img.className = "max-w-full block";
      container.appendChild(img);

      this.showModal();

      this.cropperInstance = new Cropper(img, {
        template:
          '<cropper-canvas background>' +
          '<cropper-image rotatable scalable skewable translatable></cropper-image>' +
          '<cropper-shade hidden></cropper-shade>' +
          '<cropper-handle action="select" plain></cropper-handle>' +
          '<cropper-selection initial-coverage="0.8" movable resizable initial-aspect-ratio="1" aspect-ratio="1">' +
          '<cropper-grid role="grid" bordered covered></cropper-grid>' +
          '<cropper-crosshair centered></cropper-crosshair>' +
          '<cropper-handle action="move" theme-color="rgba(255,255,255,0.35)"></cropper-handle>' +
          '<cropper-handle action="n-resize"></cropper-handle>' +
          '<cropper-handle action="e-resize"></cropper-handle>' +
          '<cropper-handle action="s-resize"></cropper-handle>' +
          '<cropper-handle action="w-resize"></cropper-handle>' +
          '<cropper-handle action="ne-resize"></cropper-handle>' +
          '<cropper-handle action="nw-resize"></cropper-handle>' +
          '<cropper-handle action="se-resize"></cropper-handle>' +
          '<cropper-handle action="sw-resize"></cropper-handle>' +
          '</cropper-selection>' +
          '</cropper-canvas>',
      });
    };
    reader.readAsDataURL(file);
  },

  async confirmCrop() {
    if (!this.cropperInstance) return;

    const selection = this.cropperInstance.getCropperSelection();
    if (!selection) return;

    try {
      const canvas = await selection.$toCanvas({
        width: 512,
        height: 512,
      });

      canvas.toBlob(
        (blob) => {
          if (!blob) return;

          const liveInput = this.getLiveInput();
          if (!liveInput) return;

          const file = new File([blob], "avatar.webp", { type: "image/webp" });
          const dataTransfer = new DataTransfer();
          dataTransfer.items.add(file);

          liveInput.files = dataTransfer.files;
          liveInput.dispatchEvent(new Event("input", { bubbles: true }));

          this.hideModal();
          this.destroyCropper();

          this.startAutoSubmitPoll();
        },
        "image/webp",
        0.9,
      );
    } catch (err) {
      console.error("Crop failed:", err);
    }
  },

  cancelCrop() {
    this.hideModal();
    this.destroyCropper();
    const fileInput = this.getFileInput();
    if (fileInput) {
      fileInput.value = "";
    }
  },

  destroyCropper() {
    if (this.cropperInstance) {
      this.cropperInstance.destroy();
      this.cropperInstance = null;
    }
  },

  showModal() {
    const modal = this.getCropperModal();
    if (modal) modal.classList.remove("hidden");
  },

  hideModal() {
    const modal = this.getCropperModal();
    if (modal) modal.classList.add("hidden");
  },

  startAutoSubmitPoll() {
    this.stopPolling();
    let attempts = 0;
    this.pollTimer = setInterval(() => {
      attempts++;
      const form = this.el.closest("form");
      const progressEl = form
        ? form.parentElement?.querySelector("[style*='width: 100%']")
        : null;

      if (progressEl || attempts > MAX_POLL_ATTEMPTS) {
        this.stopPolling();
        setTimeout(() => {
          if (form) {
            form.dispatchEvent(
              new Event("submit", { bubbles: true, cancelable: true }),
            );
          }
        }, SUBMIT_DELAY_MS);
      }
    }, POLL_INTERVAL_MS);
  },

  stopPolling() {
    if (this.pollTimer) {
      clearInterval(this.pollTimer);
      this.pollTimer = null;
    }
  },
};

export default AvatarCropper;
