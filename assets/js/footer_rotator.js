/**
 * Footer Rotator Hook
 * 
 * Rotates through different footer message suffixes with a vertical slide effect.
 * The copyright and club name remain static while the dynamic message slides in
 * from bottom and exits upward. Messages are shuffled on mount for variety.
 */

import { prefersReducedMotion } from "./spring";

const EASE = "cubic-bezier(0.32, 0.72, 0, 1)";

const FooterRotator = {
  mounted() {
    this.animationToken = 0;
    this.animation = null;
    // Array of rotating message suffixes (only the part after "The Young Scandinavians Club.")
    const baseMessages = [
      "Made with ❤️ by the YSC WebTech Team.",
      "Powered by fika and strong coffee. ☕🥐",
      "Your Nordic home in the Bay. 🇩🇰 🇫🇮 🇮🇸 🇳🇴 🇸🇪",
      "Promptly engineered with hygge. 🕯️🤖",
      "Built for the community, by the community 🤝",
      "Skål! From the YSC WebTech crew 🍻",
      "Bringing the North to the West Coast 🏔️🌊",
      "No assembly required. 🛠️🇸🇪",
      "Foggy days, warm hearts. 🌫️❤️",
      "Velkommen! From the YSC WebTech Team. ❤️",
      "Bringing the Great Outdoors to the Bay Area. 🌲🥾"
    ];
    
    // Check if we should add a seasonal message based on the current month
    const month = new Date().getMonth(); // 0-11
    const seasonalMessage = this.getSeasonalMessage(month);
    if (seasonalMessage) {
      baseMessages.push(seasonalMessage);
    }
    
    // Shuffle the messages so the order is different every visit
    this.messages = this.shuffleArray(baseMessages);
    
    // Initialize state
    this.currentIndex = 0;
    this.isPaused = false;
    
    // Apply initial message immediately so it's not empty before the first rotation
    this.updateDOM(this.messages[0], false); // false = no animation on initial load
    
    // Start the rotation after a short delay
    this.startTimeout = setTimeout(() => {
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
   * Fisher-Yates Shuffle for true randomness
   * Ensures no message repeats until all have been shown
   */
  shuffleArray(array) {
    const shuffled = [...array]; // Create a copy to avoid mutating original
    for (let i = shuffled.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
    }
    return shuffled;
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
   * Update the DOM with new message text
   * @param {string} message - The message to display
   * @param {boolean} animate - Whether to animate the change (default: true)
   *
   * The old message slides up and fades out, the text is swapped, and the new
   * message slides in from below. Web Animations keep this off the inline
   * styles (so LiveView patches can't strand it mid-transition), and a newer
   * rotation cancels one that is still running instead of racing it.
   */
  async updateDOM(message, animate = true) {
    this.animation?.cancel();
    this.animation = null;
    const token = ++this.animationToken;

    // First paint, or reduced motion: swap the text in place.
    if (!animate || prefersReducedMotion()) {
      this.el.textContent = message;
      return;
    }

    const exit = this.el.animate(
      [
        { transform: "translateY(0)", opacity: 1 },
        { transform: "translateY(-100%)", opacity: 0 },
      ],
      { duration: 250, easing: EASE, fill: "forwards" },
    );
    this.animation = exit;

    try {
      await exit.finished;
    } catch (_) {
      return; // cancelled by a newer rotation
    }
    if (token !== this.animationToken || !this.el.isConnected) return;

    this.el.textContent = message;
    const enter = this.el.animate(
      [
        { transform: "translateY(100%)", opacity: 0 },
        { transform: "translateY(0)", opacity: 1 },
      ],
      { duration: 300, easing: EASE },
    );
    exit.cancel(); // release the exit's forwards fill now that enter is running
    this.animation = enter;
  },

  /**
   * Rotate to the next message with vertical slide effect
   * Current message slides up and out, new message slides in from bottom
   */
  rotateMessage() {
    // Move to next message
    this.currentIndex = (this.currentIndex + 1) % this.messages.length;
    
    // Update the DOM with animation
    this.updateDOM(this.messages[this.currentIndex], true);
  },

    /**
     * Clean up when the component is removed
     */
    destroyed() {
        clearTimeout(this.startTimeout);
        if (this.rotationInterval) {
            clearInterval(this.rotationInterval);
        }
        this.animation?.cancel();
    }
};

export default FooterRotator;