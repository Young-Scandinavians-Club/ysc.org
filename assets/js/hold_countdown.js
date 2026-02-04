// Hold Countdown Hook for Phoenix LiveView
// Displays a live countdown timer for booking hold expiration
const HoldCountdown = {
    mounted() {
        this.initializeCountdown();
    },

    updated() {
        // Re-initialize if the expires_at time changes
        const newExpiresAt = this.el.dataset.expiresAt;
        if (newExpiresAt && newExpiresAt !== this.expiresAt) {
            this.initializeCountdown();
        }
    },

    initializeCountdown() {
        const expiresAtString = this.el.dataset.expiresAt;

        if (!expiresAtString) {
            console.error('No expiration time provided');
            return;
        }

        // Parse the expiration time (ISO format)
        this.expiresAt = new Date(expiresAtString);

        if (isNaN(this.expiresAt.getTime())) {
            console.error('Invalid expiration time format');
            return;
        }

        // Clear any existing timer
        if (this.countdownInterval) {
            clearInterval(this.countdownInterval);
        }

        // Start the countdown
        this.updateCountdown();
        this.countdownInterval = setInterval(() => {
            this.updateCountdown();
        }, 1000);
    },

    updateCountdown() {
        const now = new Date();
        const timeLeft = this.expiresAt.getTime() - now.getTime();

        if (timeLeft <= 0) {
            // Time has expired
            this.el.textContent = '00:00';
            if (this.countdownInterval) {
                clearInterval(this.countdownInterval);
            }
            return;
        }

        // Calculate time components
        const totalSeconds = Math.floor(timeLeft / 1000);
        const hours = Math.floor(totalSeconds / 3600);
        const minutes = Math.floor((totalSeconds % 3600) / 60);
        const seconds = totalSeconds % 60;

        // Format the time display (HH:MM:SS if hours > 0, otherwise MM:SS)
        let timeString;
        if (hours > 0) {
            timeString = `${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
        } else {
            timeString = `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
        }

        // Update the display (preserve tabular-nums class)
        this.el.textContent = timeString;
    },

    destroyed() {
        // Clean up the timer when the component is destroyed
        if (this.countdownInterval) {
            clearInterval(this.countdownInterval);
        }
    }
};

export default HoldCountdown;

