/**
 * Footer Rotator Hook
 *
 * Rotates through different footer message suffixes with a vertical slide effect.
 * The copyright and club name remain static while the dynamic message slides in
 * from bottom and exits upward.
 */

const FooterRotator = {
    mounted() {
        // Array of rotating message suffixes (only the part after "The Young Scandinavians Club.")
        this.messages = [
            "Made with ❤️ by the YSC WebTech Team.",
            "Powered by fika and strong coffee. ☕🥐",
            "Your Nordic home in the Bay. 🇩🇰 🇫🇮 🇮🇸 🇳🇴 🇸🇪",
            "Crafted with hygge 🕯️ in the SF Bay.",
            "Bringing the Great Outdoors to the Bay Area. 🌲🥾",
            "Built for the community, by the community 🤝",
            "Velkommen! From the YSC WebTech Team. ❤️",
            "Skål! From the YSC WebTech crew 🍻"
        ];

        // Check if we should add a seasonal message based on the current month
        const month = new Date().getMonth(); // 0-11
        const seasonalMessage = this.getSeasonalMessage(month);
        if (seasonalMessage) {
            // Insert seasonal message at position 2 (middle of rotation)
            this.messages.splice(2, 0, seasonalMessage);
        }

        // Initialize state
        this.currentIndex = 0;
        this.isPaused = false;

        // Start the rotation after a short delay
        setTimeout(() => {
            this.startRotation();
        }, 5000); // Wait 5 seconds before first rotation

        // Pause rotation on hover for better UX
        this.el.addEventListener("mouseenter", () => {
            this.isPaused = true;
        });

        this.el.addEventListener("mouseleave", () => {
            this.isPaused = false;
        });
    },

    /**
     * Get a seasonal message suffix based on the current month
     * Enhanced with authentic Nordic celebrations!
     */
    getSeasonalMessage(month) {
        // December (God Jul!)
        if (month === 11) {
            return "God Jul & Hyggelige hilsener! 🎅🎄";
        }
        // May (Norway Constitution Day / Spring)
        if (month === 4) {
            return "Celebrating Spring & Syttende Mai! 🇳🇴🎈";
        }
        // June (Midsummer - Midsommar!)
        if (month === 5) {
            return "Glad Midsommar! 🌸🇸🇪🌻";
        }
        // October (Cozy Season)
        if (month === 9) {
            return "High season for candles & hygge. 🕯️🍂";
        }
        // January-February (Winter Coziness)
        if (month === 0 || month === 1) {
            return "Stay cozy out there! ❄️☕";
        }
        return null;
    },

    /**
     * Start the rotation timer
     */
    startRotation() {
        this.rotationInterval = setInterval(() => {
            if (!this.isPaused) {
                this.rotateMessage();
            }
        }, 12000); // Rotate every 12 seconds
    },

    /**
     * Rotate to the next message with vertical slide effect
     * Current message slides up and out, new message slides in from bottom
     */
    rotateMessage() {
        // Start slide up animation (exit)
        this.el.style.transform = "translateY(-100%)";
        this.el.style.opacity = "0";

        // After exit animation completes, change text and slide in from bottom
        setTimeout(() => {
            // Move to next message
            this.currentIndex = (this.currentIndex + 1) % this.messages.length;

            // Update the text content
            this.el.textContent = this.messages[this.currentIndex];

            // Reset position to bottom (ready to slide in)
            this.el.style.transform = "translateY(100%)";
            this.el.style.opacity = "0";

            // Small delay before starting entry animation
            requestAnimationFrame(() => {
                requestAnimationFrame(() => {
                    // Slide in from bottom to center
                    this.el.style.transform = "translateY(0)";
                    this.el.style.opacity = "1";
                });
            });
        }, 400); // Match exit animation duration
    },

    /**
     * Clean up when the component is removed
     */
    destroyed() {
        if (this.rotationInterval) {
            clearInterval(this.rotationInterval);
        }
    }
};

export default FooterRotator;