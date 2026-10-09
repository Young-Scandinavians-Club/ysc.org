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

        // True while a keyboard user has focus inside the carousel. Only
        // :focus-visible counts: clicking a dot with a mouse also focuses its
        // radio, and that must not freeze the carousel until the next click.
        const keyboardFocusInside = () => container.querySelector(':focus-visible') !== null;

        // Start autoplay. Never for users who asked for reduced motion (they can
        // still step through slides with the controls), and never while the
        // pointer is over the carousel or keyboard focus is inside it. The check
        // lives here, not in each caller, because several callers restart
        // autoplay on a delay and would otherwise resume under a focused user.
        const startAutoplay = () => {
            if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
            if (container.matches(':hover') || keyboardFocusInside()) return;
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

        // Pause while keyboard focus is inside; resume once it leaves.
        const handleFocusIn = (event) => {
            if (event.target.matches(':focus-visible')) stopAutoplay();
        };

        const handleFocusOut = () => {
            // Focus has not settled on its next element yet; check on the next tick.
            setTimeout(startAutoplay, 0);
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
        container.addEventListener('focusin', handleFocusIn);
        container.addEventListener('focusout', handleFocusOut);

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
            container.removeEventListener('focusin', handleFocusIn);
            container.removeEventListener('focusout', handleFocusOut);
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