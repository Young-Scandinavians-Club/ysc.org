import "../vendor/confetti.browser.min.js";

// Confetti hook for celebratory moments
// Uses canvas-confetti library (imported and bundled)
// The UMD module sets window.confetti when imported
const Confetti = {
    mounted() {
        // Only fire confetti if the data attribute indicates it should
        const showConfetti = this.el.dataset.showConfetti === 'true';
        console.log('[Confetti] Hook mounted, showConfetti:', showConfetti, 'data attribute:', this.el.dataset.showConfetti);
        if (showConfetti) {
            // Library is already imported, fire immediately
            this.fireConfetti();
        }
    },

    fireConfetti() {
        console.log('[Confetti] Firing confetti animation');
        // The UMD module sets window.confetti when imported
        const confettiFn = window.confetti;

        if (typeof confettiFn !== 'function') {
            console.error('[Confetti] Function not available:', typeof confettiFn);
            return;
        }

        // Scandinavian "Midsummer Petals" style
        // Muted Nordic palette: soft white, cream, pale yellow, light blue
        const nordicColors = ['#f8fafc', '#bae6fd', '#fef08a', '#e2e8f0'];

        // Gentle drift from top - multiple small bursts across the top
        // Creates a calm, organic "petal fall" effect
        const burstCount = 5;
        const burstInterval = 300; // Space out the bursts for a gentle cascade

        for (let i = 0; i < burstCount; i++) {
            setTimeout(() => {
                try {
                    confettiFn({
                        particleCount: 30,
                        spread: 70,
                        origin: {
                            x: Math.random() * 0.6 + 0.2, // Spread across 20% to 80% of screen width
                            y: 0.1 // Start from top, like petals drifting down
                        },
                        colors: nordicColors,
                        gravity: 0.6, // Slower, more gentle fall - like a light breeze
                        ticks: 300, // Longer animation for calm, drifting effect
                        scalar: 0.8, // Slightly smaller particles for subtlety
                        startVelocity: 15 // Lower initial velocity for gentle descent
                    });
                    console.log(`[Confetti] Burst ${i + 1} fired`);
                } catch (error) {
                    console.error('[Confetti] Error firing confetti:', error);
                }
            }, i * burstInterval);
        }
    }
};

export default Confetti;