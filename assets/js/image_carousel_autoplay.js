export default {
    mounted() {
        // Find the carousel container (it's a child of the hook element)
        const container = this.el.querySelector('.image-carousel-container') || this.el;

        // Find all radio buttons for this carousel
        const radioButtons = container.querySelectorAll('input[type="radio"]');
        if (radioButtons.length === 0) return;

        let currentIndex = 0;
        let autoplayInterval = null;
        const autoplayDelay = 5000; // 5 seconds

        // Find the current checked radio button
        const getCurrentIndex = () => {
            return Array.from(radioButtons).findIndex(radio => radio.checked);
        };

        // Advance to next slide
        const nextSlide = () => {
            currentIndex = getCurrentIndex();
            if (currentIndex === -1) currentIndex = 0;

            const nextIndex = (currentIndex + 1) % radioButtons.length;
            const nextRadio = radioButtons[nextIndex];
            if (nextRadio) {
                nextRadio.checked = true;
                // Trigger change event to update CSS
                nextRadio.dispatchEvent(new Event('change', { bubbles: true }));
            }
        };

        // Start autoplay
        const startAutoplay = () => {
            if (autoplayInterval) return; // Already running
            autoplayInterval = setInterval(nextSlide, autoplayDelay);
        };

        // Stop autoplay
        const stopAutoplay = () => {
            if (autoplayInterval) {
                clearInterval(autoplayInterval);
                autoplayInterval = null;
            }
        };

        // Pause on hover/interaction
        const handleMouseEnter = () => {
            stopAutoplay();
        };

        const handleMouseLeave = () => {
            startAutoplay();
        };

        // Pause when user clicks navigation
        const handleInteraction = () => {
            stopAutoplay();
            // Resume after delay
            setTimeout(() => {
                if (!container.matches(':hover')) {
                    startAutoplay();
                }
            }, autoplayDelay * 2);
        };

        // Attach event listeners
        container.addEventListener('mouseenter', handleMouseEnter);
        container.addEventListener('mouseleave', handleMouseLeave);

        // Listen for navigation clicks (buttons and dots)
        const navButtons = container.querySelectorAll('.carousel-nav, .carousel-dot, label[for^="slide-"]');
        navButtons.forEach(button => {
            button.addEventListener('click', handleInteraction);
        });

        // Listen for radio button changes (user interaction)
        radioButtons.forEach(radio => {
            radio.addEventListener('change', () => {
                if (!container.matches(':hover')) {
                    // If not hovering, restart autoplay after a delay
                    stopAutoplay();
                    setTimeout(startAutoplay, autoplayDelay);
                }
            });
        });

        // Start autoplay initially
        startAutoplay();

        // Store cleanup function
        this.cleanup = () => {
            stopAutoplay();
            container.removeEventListener('mouseenter', handleMouseEnter);
            container.removeEventListener('mouseleave', handleMouseLeave);
            navButtons.forEach(button => {
                button.removeEventListener('click', handleInteraction);
            });
        };
    },

    destroyed() {
        if (this.cleanup) {
            this.cleanup();
        }
    }
};