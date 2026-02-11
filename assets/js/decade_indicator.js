export default {
    mounted() {
        this.indicator = document.getElementById("current-decade-indicator");
        this.decadeWatermarks = document.querySelectorAll(".decade-watermark");

        if (!this.indicator) return;

        const handleScroll = () => {
            const scrollPosition = window.scrollY + (window.innerHeight * 0.3); // Check at 30% down the viewport

            // Find the currently visible decade
            const startYear = 1950;
            const currentYear = new Date().getFullYear();
            const diff = currentYear - startYear; // e.g., 74

            const roundedYears = Math.floor(diff / 5) * 5; // e.g., 70
            let currentDecade = "Exploring " + roundedYears + " Years";
            let found = false;

            // Convert NodeList to Array and reverse to check from bottom up
            const watermarksArray = Array.from(this.decadeWatermarks);

            for (let i = watermarksArray.length - 1; i >= 0; i--) {
                const watermark = watermarksArray[i];
                const rect = watermark.getBoundingClientRect();
                const elementTop = rect.top + window.scrollY;

                // If we've scrolled past this decade marker
                if (scrollPosition >= elementTop) {
                    currentDecade = watermark.textContent.trim();
                    found = true;
                    break;
                }
            }

            // Update the indicator text with smooth transition
            if (this.indicator.textContent !== currentDecade) {
                this.indicator.style.transition = "opacity 0.3s ease-out, transform 0.3s ease-out";
                this.indicator.style.opacity = "0";
                this.indicator.style.transform = "translateY(-4px)";

                setTimeout(() => {
                    this.indicator.textContent = currentDecade;
                    this.indicator.style.opacity = "1";
                    this.indicator.style.transform = "translateY(0)";
                }, 300);
            }
        };

        // Throttle scroll events for better performance
        let ticking = false;
        const throttledScroll = () => {
            if (!ticking) {
                window.requestAnimationFrame(() => {
                    handleScroll();
                    ticking = false;
                });
                ticking = true;
            }
        };

        // Listen for scroll events
        window.addEventListener("scroll", throttledScroll, { passive: true });

        // Initial check
        handleScroll();

        // Store the handler for cleanup
        this.throttledScroll = throttledScroll;
    },

    destroyed() {
        if (this.throttledScroll) {
            window.removeEventListener("scroll", this.throttledScroll);
        }
    }
};