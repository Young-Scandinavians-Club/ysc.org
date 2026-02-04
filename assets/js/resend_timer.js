// Resend Timer Hook - handles countdown timers for resend buttons
export default {
    mounted() {
        this.interval = setInterval(() => {
            // Check if there are any countdown elements
            const countdownElements = this.el.querySelectorAll('[data-countdown]');

            if (countdownElements.length > 0) {
                // Update countdown timers
                countdownElements.forEach(element => {
                    const countdownValue = element.dataset.countdown;
                    const remaining = parseInt(countdownValue, 10);

                    // Ensure we have a valid number
                    if (isNaN(remaining) || remaining <= 0) {
                        // Invalid or expired countdown, trigger expiration
                        const timerType = element.dataset.timerType || 'unknown';
                        this.pushEvent('resend_timer_expired', { type: timerType });
                        element.style.display = 'none';
                        return;
                    }

                    if (remaining > 1) {
                        element.dataset.countdown = remaining - 1;
                        element.textContent = `resend in ${remaining - 1}s`;
                    } else {
                        // Timer expired, notify server to update state
                        const timerType = element.dataset.timerType || 'unknown';
                        this.pushEvent('resend_timer_expired', { type: timerType });
                        // Hide the countdown element
                        element.style.display = 'none';
                    }
                });
            }
        }, 1000);
    },

    destroyed() {
        if (this.interval) {
            clearInterval(this.interval);
        }
    }
};