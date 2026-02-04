// CountdownColor hook - Updates timer colors based on remaining time
const CountdownColor = {
    mounted() {
        this.updateColors();
        // Update every second
        this.interval = setInterval(() => this.updateColors(), 1000);
    },

    destroyed() {
        if (this.interval) {
            clearInterval(this.interval);
        }
    },

    updated() {
        this.updateColors();
    },

    updateColors() {
        const expiresAt = this.el.dataset.expiresAt;
        if (!expiresAt) return;

        const now = new Date();
        const expires = new Date(expiresAt);
        const diffMs = expires - now;
        const diffSeconds = Math.floor(diffMs / 1000);

        if (diffSeconds <= 0) {
            // Expired - red
            this.setColorScheme("red", true);
            return;
        }

        const minutes = Math.floor(diffSeconds / 60);
        const seconds = diffSeconds % 60;

        const container = this.el;
        const header = container.querySelector("#countdown-header");
        const text = container.querySelector("#countdown-text");
        const countdown = container.querySelector("#hold-countdown");

        if (minutes < 1) {
            // Less than 1 minute - red with pulse
            this.setColorScheme("red", true);
            if (countdown) {
                countdown.classList.add("animate-pulse");
            }
        } else if (minutes < 5) {
            // Less than 5 minutes - amber
            this.setColorScheme("amber", false);
            if (countdown) {
                countdown.classList.remove("animate-pulse");
            }
        } else {
            // 5+ minutes - blue
            this.setColorScheme("blue", false);
            if (countdown) {
                countdown.classList.remove("animate-pulse");
            }
        }
    },

    setColorScheme(color, pulse) {
        const container = this.el;
        const header = container.querySelector("#countdown-header");
        const text = container.querySelector("#countdown-text");

        // Remove all color classes
        container.classList.remove(
            "bg-blue-50", "border-blue-200",
            "bg-amber-50", "border-amber-200",
            "bg-rose-50", "border-rose-200",
            "border-red-500"
        );
        if (header) {
            header.classList.remove(
                "text-blue-800",
                "text-amber-800",
                "text-rose-800"
            );
        }
        if (text) {
            text.classList.remove(
                "text-blue-700",
                "text-amber-700",
                "text-rose-700"
            );
        }

        // Apply new color scheme
        switch (color) {
            case "red":
                container.classList.add("bg-rose-50", "border-rose-200");
                if (pulse) {
                    container.classList.add("border-red-500");
                }
                if (header) {
                    header.classList.add("text-rose-800");
                }
                if (text) {
                    text.classList.add("text-rose-700");
                }
                break;
            case "amber":
                container.classList.add("bg-amber-50", "border-amber-200");
                if (header) {
                    header.classList.add("text-amber-800");
                }
                if (text) {
                    text.classList.add("text-amber-700");
                }
                break;
            case "blue":
            default:
                container.classList.add("bg-blue-50", "border-blue-200");
                if (header) {
                    header.classList.add("text-blue-800");
                }
                if (text) {
                    text.classList.add("text-blue-700");
                }
                break;
        }
    }
};

export default CountdownColor;