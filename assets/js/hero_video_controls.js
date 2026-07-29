/**
 * Pause/play control for the hero background video.
 * Mount on the hero section; expects a <video> and a button with data-hero-video-toggle.
 * Toggles video playback on button click and keeps the button icon in sync (pause when playing, play when paused).
 *
 * Intentionally does not rely on the HTML autoplay attribute: Phoenix LiveView's
 * morphdom calls video.play() on autoplay nodes without catching rejections, which
 * surfaces as unhandled NotAllowedError on iOS Safari.
 */
export default {
    mounted() {
        this.video = this.el.querySelector("video");
        this.button = this.el.querySelector("[data-hero-video-toggle]");
        if (!this.video || !this.button) return;

        this.updateButtonState = () => {
            if (this.video.paused) {
                this.button.classList.add("paused");
                this.button.setAttribute("aria-label", "Play video");
            } else {
                this.button.classList.remove("paused");
                this.button.setAttribute("aria-label", "Pause video");
            }
        };

        this.toggle = () => {
            if (this.video.paused) {
                this.safePlay();
            } else {
                this.video.pause();
            }
            this.updateButtonState();
        };

        this.button.addEventListener("click", this.toggle);
        this.video.addEventListener("play", this.updateButtonState);
        this.video.addEventListener("pause", this.updateButtonState);

        this.safePlay();
        this.updateButtonState();
    },

    safePlay() {
        if (!this.video) return;
        // Promise.resolve handles browsers where play() returns undefined instead of a Promise.
        Promise.resolve(this.video.play()).catch(() => {});
    },

    destroyed() {
        if (this.button) this.button.removeEventListener("click", this.toggle);
        if (this.video) {
            this.video.removeEventListener("play", this.updateButtonState);
            this.video.removeEventListener("pause", this.updateButtonState);
        }
    },
};
