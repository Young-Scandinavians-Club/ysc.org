/**
 * Pause/play control for the hero background video.
 * Mount on the hero section; expects a <video> and a button with data-hero-video-toggle.
 * Toggles video playback on button click and keeps the button icon in sync (pause when playing, play when paused).
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
                Promise.resolve(this.video.play()).catch(() => {});
            } else {
                this.video.pause();
            }
            this.updateButtonState();
        };

        this.button.addEventListener("click", this.toggle);
        this.video.addEventListener("play", this.updateButtonState);
        this.video.addEventListener("pause", this.updateButtonState);

        // Suppress unhandled rejections from autoplay being interrupted by the browser
        // (e.g. power-saving policies, tab backgrounded during LiveView navigation).
        // Promise.resolve handles browsers where play() returns undefined instead of a Promise.
        if (this.video.paused) {
            Promise.resolve(this.video.play()).catch(() => {});
        }

        this.updateButtonState();
    },

    destroyed() {
        if (this.button) this.button.removeEventListener("click", this.toggle);
        if (this.video) {
            this.video.removeEventListener("play", this.updateButtonState);
            this.video.removeEventListener("pause", this.updateButtonState);
        }
    },
};